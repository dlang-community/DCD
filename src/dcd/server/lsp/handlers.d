/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2014 Brian Schott
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://wwwwww.gnu.org/licenses/>.
 */

module dcd.server.lsp.handlers;

import std.algorithm;
import std.array;
import std.conv;
import std.experimental.logger;
import std.json;
import std.string;

import dcd.common.messages;
import dcd.server.autocomplete;
import dcd.server.autocomplete.util : clampedBucketCount;
import dcd.server.lsp.document;
import dcd.server.lsp.protocol;
import dcd.server.lsp.jsonrpc;

import containers.hashset;
import dsymbol.modulecache;
import dsymbol.builtin.names : IMPORT_SYMBOL_NAME, CONSTRUCTOR_SYMBOL_NAME,
	DESTRUCTOR_SYMBOL_NAME, UNITTEST_SYMBOL_NAME;
import dsymbol.symbol : CompletionKind, DSymbol, isPublicCompletionKind;

/**
 * Shared server state passed to all handlers.
 */
struct ServerContext
{
	/// The module cache used for semantic analysis.
	ModuleCache* cache;

	/// The open document store.
	DocumentStore documents;

	/// The position converter for offset/position translation.
	PositionConverter converter;

	/// The root URI of the workspace, if any.
	string rootUri;

	/// The server's capabilities, set after `initialize`.
	JSONValue clientCapabilities;
}

/**
 * The result of handling a message: either a response value or an error.
 */
struct HandlerResult
{
	/// The result value.
	JSONValue result;

	/// True if `result` holds a value to send.
	bool hasResult;

	/// The error code, 0 for success.
	int errorCode;

	/// The error message.
	string errorMessage;

	/// A successful result.
	this(JSONValue result)
	{
		this.result = result;
		this.hasResult = true;
	}

	/// An error result.
	this(JSONValue result, int errorCode, string errorMessage)
	{
		this.result = result;
		this.errorCode = errorCode;
		this.errorMessage = errorMessage;
	}
}

/**
 * Handles an incoming request or notification after `initialize`.
 *
 * Params:
 *     context = shared server state
 *     method = the LSP method name
 *     params = the request params
 * Returns:
 *     the handler result
 */
HandlerResult handleRequest(ref ServerContext context, string method, JSONValue params)
{
	try
	{
		switch (method)
		{
		case "initialize":
			return handleInitialize(context, params);
		case "initialized":
			return HandlerResult(); // notification, no response
		case "shutdown":
			return HandlerResult(JSONValue(null));
		case "textDocument/didOpen":
			handleDidOpen(context, params);
			return HandlerResult();
		case "textDocument/didChange":
			handleDidChange(context, params);
			return HandlerResult();
		case "textDocument/didClose":
			handleDidClose(context, params);
			return HandlerResult();
		case "textDocument/completion":
			return HandlerResult(handleCompletion(context, params));
		case "textDocument/hover":
			return HandlerResult(handleHover(context, params));
		case "textDocument/definition":
			return HandlerResult(handleDefinition(context, params));
		case "textDocument/references":
			return HandlerResult(handleReferences(context, params));
		case "textDocument/signatureHelp":
			return HandlerResult(handleSignatureHelp(context, params));
		case "textDocument/inlayHint":
			return HandlerResult(handleInlayHint(context, params));
		case "textDocument/documentSymbol":
			return HandlerResult(handleDocumentSymbol(context, params));
		case "$/cancelRequest":
			return HandlerResult(); // no-op, we don't support cancellation
		default:
			return HandlerResult(JSONValue.init,
				JsonRpcErrorCode.methodNotFound,
				"Method not found: " ~ method);
		}
	}
	catch (Exception e)
	{
		warningf("Error handling %s: %s", method, e.msg);
		return HandlerResult(JSONValue.init,
			JsonRpcErrorCode.internalError,
			"Internal error: " ~ e.msg);
	}
}

/**
 * Handles the `initialize` request.
 */
HandlerResult handleInitialize(ref ServerContext context, JSONValue params)
{
	if ("rootUri" in params && params["rootUri"].type == JSONType.string)
		context.rootUri = params["rootUri"].str;
	else if ("rootPath" in params && params["rootPath"].type == JSONType.string)
		context.rootUri = params["rootPath"].str;
	else if ("workspaceFolders" in params
		&& params["workspaceFolders"].type == JSONType.array
		&& params["workspaceFolders"].array.length > 0)
	{
		// Some clients only send workspaceFolders instead of rootUri
		auto first = params["workspaceFolders"].array[0];
		if ("uri" in first && first["uri"].type == JSONType.string)
			context.rootUri = first["uri"].str;
	}
	if ("capabilities" in params)
		context.clientCapabilities = params["capabilities"];

	// Negotiate position encoding: prefer UTF-8 (byte offsets, what DCD
	// uses internally), fall back to UTF-16 (the LSP default) if the client
	// doesn't support it.
	bool clientSupportsUtf8;
	if (context.clientCapabilities.type == JSONType.object
		&& "general" in context.clientCapabilities
		&& context.clientCapabilities["general"].type == JSONType.object
		&& "positionEncodings" in context.clientCapabilities["general"]
		&& context.clientCapabilities["general"]["positionEncodings"].type == JSONType.array)
	{
		foreach (enc; context.clientCapabilities["general"]["positionEncodings"].array)
			if (enc.type == JSONType.string && enc.str == "utf-8")
				clientSupportsUtf8 = true;
	}
	if (clientSupportsUtf8)
	{
		context.documents = new DocumentStore(PositionEncoding.utf8);
		context.converter = PositionConverter(PositionEncoding.utf8);
	}
	else
	{
		context.documents = new DocumentStore(PositionEncoding.utf16);
		context.converter = PositionConverter(PositionEncoding.utf16);
	}

	// Read import paths from initializationOptions
	string[] importPaths;
	if ("initializationOptions" in params)
	{
		auto options = params["initializationOptions"];
		if (options.type == JSONType.object
			&& "importPaths" in options
			&& options["importPaths"].type == JSONType.array)
		{
			foreach (path; options["importPaths"].array)
				if (path.type == JSONType.string)
					importPaths ~= path.str;
		}
	}
	context.cache.addImportPaths(importPaths);

	// Auto-detect import paths on the server so that any LSP client (not
	// just the VS Code extension) gets module search out of the box: the
	// workspace's own source directories and the local Phobos installation.
	auto detected = detectWorkspaceImportPaths(context.rootUri);
	auto phobos = detectPhobosImportPaths();
	if (!phobos.empty)
		detected ~= phobos;
	if (!detected.empty)
	{
		infof("Auto-detected import paths:\n    %-(%s\n    %)", detected);
		context.cache.addImportPaths(detected);
	}

	// Build the server capabilities response
	JSONValue capabilities = parseJSON(`{}`);
	capabilities["positionEncoding"] = JSONValue(clientSupportsUtf8 ? "utf-8" : "utf-16");
	capabilities["textDocumentSync"] = JSONValue(cast(int) TextDocumentSyncKind.full);
	JSONValue completionProvider = parseJSON(`{}`);
	completionProvider["resolveProvider"] = JSONValue(false);
	completionProvider["triggerCharacters"] = JSONValue(["."]);
	capabilities["completionProvider"] = completionProvider;
	capabilities["hoverProvider"] = JSONValue(true);
	capabilities["definitionProvider"] = JSONValue(true);
	capabilities["referencesProvider"] = JSONValue(true);
	capabilities["documentSymbolProvider"] = JSONValue(true);
	capabilities["inlayHintProvider"] = JSONValue(true);
	JSONValue signatureHelpProvider = parseJSON(`{}`);
	signatureHelpProvider["triggerCharacters"] = JSONValue(["(", ","]);
	capabilities["signatureHelpProvider"] = signatureHelpProvider;

	JSONValue result = parseJSON(`{}`);
	result["capabilities"] = capabilities;
	result["serverInfo"] = serverInfo();
	return HandlerResult(result);
}

/**
 * Auto-detects the workspace's own import directories from the workspace
 * root: the standard dub layouts (source/, src/, import/) plus the root
 * itself. Runs on the server so that every LSP client — not just the VS
 * Code extension — resolves the project's own modules out of the box.
 */
private string[] detectWorkspaceImportPaths(string rootUri)
{
	import std.file : exists, isDir;
	import std.path : buildPath;

	if (rootUri.empty)
		return [];
	string root = uriToPath(rootUri);
	if (root.empty || !exists(root) || !isDir(root))
		return [];

	string[] result;
	foreach (dir; ["source", "src", "import"])
	{
		string p = buildPath(root, dir);
		if (exists(p) && isDir(p))
			result ~= p;
	}
	// The root itself: modules may live at the top level.
	result ~= root;
	return result;
}

/**
 * Auto-detects the import directory of a locally installed D compiler
 * (Homebrew LDC, system LDC, or DMD via the install script) so that
 * `import std.*` resolves without any client-side configuration.
 */
private string[] detectPhobosImportPaths()
{
	import std.algorithm : map, sort;
	import std.array : array;
	import std.file : dirEntries, exists, isDir, SpanMode;
	import std.path : baseName, buildPath, expandTilde;

	string[] candidates;

	// Homebrew LDC: /opt/homebrew/Cellar/ldc/<version>/include/dlang/ldc
	immutable ldcCellar = "/opt/homebrew/Cellar/ldc";
	if (exists(ldcCellar) && isDir(ldcCellar))
	{
		auto versions = dirEntries(ldcCellar, SpanMode.shallow)
			.map!(a => a.name).array;
		sort!((a, b) => a > b)(versions); // newest first (lexicographic)
		foreach (v; versions)
			candidates ~= buildPath(v, "include", "dlang", "ldc");
	}

	// System-wide LDC
	candidates ~= "/usr/local/include/dlang/ldc";
	candidates ~= "/usr/include/dlang/ldc";

	// DMD via the install script: ~/dlang/dmd-<version>/src/{phobos,druntime}
	immutable dlangDir = expandTilde("~/dlang");
	if (exists(dlangDir) && isDir(dlangDir))
	{
		auto dirs = dirEntries(dlangDir, SpanMode.shallow)
			.map!(a => a.name).array;
		sort!((a, b) => a > b)(dirs);
		foreach (d; dirs)
			if (baseName(d).startsWith("dmd-"))
			{
				candidates ~= buildPath(d, "src", "phobos");
				candidates ~= buildPath(d, "src", "druntime", "import");
			}
	}

	foreach (c; candidates)
		if (exists(buildPath(c, "std")))
			return [c];
	return [];
}

/**
 * Builds the serverInfo object.
 */
JSONValue serverInfo()
{
	import dcd.common.dcd_version : DCD_VERSION;

	JSONValue info = parseJSON(`{}`);
	info["name"] = JSONValue("dcd-lsp");
	info["version"] = JSONValue(DCD_VERSION);
	return info;
}

/**
 * Handles `textDocument/didOpen`.
 */
void handleDidOpen(ref ServerContext context, JSONValue params)
{
	auto textDocument = params["textDocument"];
	string uri = textDocument["uri"].str;
	string languageId = "languageId" in textDocument
		? textDocument["languageId"].str : "d";
	long docVersion = textDocument["version"].integer;
	string text = textDocument["text"].str;
	context.documents.didOpen(uri, languageId, docVersion, text);
}

/**
 * Handles `textDocument/didChange` (full document sync).
 */
void handleDidChange(ref ServerContext context, JSONValue params)
{
	auto textDocument = params["textDocument"];
	string uri = textDocument["uri"].str;
	long docVersion = textDocument["version"].integer;

	// Full sync: take the last content change
	auto changes = params["contentChanges"].array;
	if (changes.empty)
		return;
	auto last = changes[$ - 1];
	if ("range" in last)
	{
		// Incremental change not supported, but we handle it gracefully by
		// ignoring it since we declared full sync. Log a warning.
		warning("Received incremental change for ", uri,
			" but only full sync is supported");
		return;
	}
	context.documents.didChange(uri, docVersion, last["text"].str);
}

/**
 * Handles `textDocument/didClose`.
 */
void handleDidClose(ref ServerContext context, JSONValue params)
{
	string uri = params["textDocument"]["uri"].str;
	context.documents.didClose(uri);
}

/**
 * Builds an `AutocompleteRequest` for the document at the given position.
 */
private AutocompleteRequest buildRequest(ref ServerContext context, JSONValue params)
{
	auto textDocument = params["textDocument"];
	string uri = textDocument["uri"].str;
	auto doc = context.documents.get(uri);
	enforceDoc(doc, uri);

	Position pos = Position.fromJson(params["position"]);
	size_t offset = context.converter.toOffset(*doc, pos);

	AutocompleteRequest request;
	request.fileName = uriToPath(uri);
	request.sourceCode = cast(ubyte[]) doc.text.dup;
	request.cursorPosition = offset;
	return request;
}

private void enforceDoc(TextDocument* doc, string uri)
{
	import std.exception : enforce;
	enforce(doc !is null, "Document not open: " ~ uri);
}

/**
 * Builds an `AutocompleteRequest` for a symbol query (definition, hover,
 * references) at the given position.
 *
 * DCD's `cursorPosition` counts the bytes *before* the cursor, and tokens
 * are collected with `token.index < cursorPosition`, where `token.index` is
 * the offset of the token's FIRST byte. A cursor sitting on the first
 * character of an identifier therefore excludes that identifier from the
 * token chain and the lookup fails. For symbol queries (unlike completion,
 * where the cursor is naturally after the typed text) the position is ON the
 * symbol, so nudge the offset one byte into the token when needed.
 */
private AutocompleteRequest buildSymbolRequest(ref ServerContext context, JSONValue params)
{
	auto request = buildRequest(context, params);

	// If the offset lands exactly on the first byte of an identifier token,
	// advance by one so the token is included in the "before cursor" set.
	if (request.cursorPosition < request.sourceCode.length)
	{
		immutable c = request.sourceCode[request.cursorPosition];
		if (isIdentChar(c) && (request.cursorPosition == 0
				|| !isIdentChar(request.sourceCode[request.cursorPosition - 1])))
			request.cursorPosition++;
	}
	return request;
}

private bool isIdentChar(ubyte c)
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
		|| (c >= '0' && c <= '9') || c == '_';
}

/**
 * Converts a file URI to a filesystem path.
 */
string uriToPath(string uri)
{
	import std.uri : decode;

	if (uri.startsWith("file://"))
	{
		string path = uri["file://".length .. $];
		// strip authority component if present
		if (path.startsWith("//"))
			path = path[2 .. $];
		return decodeComponent(path);
	}
	return uri;
}

private string decodeComponent(string s)
{
	import std.uri : decodeComponent;
	try
		return s.decodeComponent;
	catch (Exception e)
		return s;
}

/**
 * Converts a filesystem path to a file URI.
 */
string pathToUri(string path)
{
	import std.uri : encodeComponent;

	if (path.empty)
		return path;
	// encode each path segment
	auto segments = path.splitter('/');
	string[] encodedSegments;
	foreach (segment; segments)
		encodedSegments ~= encodeComponent(segment);
	string encoded = encodedSegments.join("/");
	if (path.startsWith("/"))
		encoded = "/" ~ encoded;
	// "file://" + "/opt/..." would give "file:////opt/..." (empty leading
	// segment from splitter); collapse duplicate slashes so the URI is
	// exactly "file:///opt/..."
	while (encoded.startsWith("//"))
		encoded = encoded[1 .. $];
	return "file://" ~ encoded;
}

/**
 * Handles `textDocument/completion`.
 */
JSONValue handleCompletion(ref ServerContext context, JSONValue params)
{
	auto request = buildRequest(context, params);
	auto response = complete(request, *context.cache);

	if (response.completionType == CompletionType.calltips)
	{
		// A calltip response to a completion request means the client typed
		// "(", send signature help instead
		return signatureHelpFromResponse(response).toJson();
	}

	CompletionList list;
	list.isIncomplete = false;
	foreach (completion; response.completions)
	{
		CompletionItem item;
		item.label = completion.identifier;
		item.kind = toCompletionItemKind(cast(CompletionKind) completion.kind);
		item.detail = completion.typeOf;
		item.documentation = completion.documentation;
		list.items ~= item;
	}
	return list.toJson();
}

/**
 * Handles `textDocument/hover`.
 */
JSONValue handleHover(ref ServerContext context, JSONValue params)
{
	auto request = buildSymbolRequest(context, params);
	auto response = getDoc(request, *context.cache);

	if (response.completions.empty)
		return JSONValue(null);

	auto completion = response.completions[0];
	Hover hover;
	string contents = completion.definition;
	if (completion.documentation.length)
		contents ~= "\n\n" ~ completion.documentation;
	hover.contents = contents;
	return hover.toJson();
}

/**
 * Handles `textDocument/definition`.
 */
JSONValue handleDefinition(ref ServerContext context, JSONValue params)
{
	auto request = buildSymbolRequest(context, params);
	auto response = findDeclaration(request, *context.cache);

	if (response.symbolFilePath.empty)
		return JSONValue(null);

	Location location;
	// DCD reports the analyzed (in-memory) document as "stdin"; map it back
	// to the requesting document's URI.
	if (response.symbolFilePath == "stdin")
	{
		auto doc = context.documents.get(params["textDocument"]["uri"].str);
		Position start = doc !is null
			? context.converter.toPosition(*doc, response.symbolLocation)
			: Position(0, 0);
		location.uri = params["textDocument"]["uri"].str;
		location.range = Range(start, start);
	}
	else
	{
		// The symbol lives in another file: symbolLocation is an offset into
		// THAT file, so it must be converted against that file's content,
		// not the requesting document's (which would be out of bounds).
		location.uri = pathToUri(response.symbolFilePath);
		location.range = Range(positionInFile(context,
			response.symbolFilePath, response.symbolLocation));
	}
	return location.toJson();
}

/**
 * Converts a byte offset in an on-disk file to an LSP position.
 *
 * The file is read and indexed on demand; if it cannot be read the offset
 * degrades to line 0.
 */
private Position positionInFile(ref ServerContext context, string filePath, size_t offset)
{
	import std.file : exists, readText;

	if (!exists(filePath))
		return Position(0, 0);
	TextDocument fileDoc;
	fileDoc.text = readText(filePath);
	fileDoc.reindex();
	if (offset > fileDoc.text.length)
		return Position(0, 0);
	return context.converter.toPosition(fileDoc, offset);
}

/**
 * Handles `textDocument/references`.
 */
JSONValue handleReferences(ref ServerContext context, JSONValue params)
{
	auto request = buildSymbolRequest(context, params);
	auto response = findLocalUse(request, *context.cache);

	if (response.completions.empty)
		return JSONValue(null);

	auto doc = context.documents.get(params["textDocument"]["uri"].str);
	JSONValue[] locations;
	foreach (completion; response.completions)
	{
		Position pos;
		if (completion.symbolFilePath == "stdin")
		{
			pos = doc !is null
				? context.converter.toPosition(*doc, completion.symbolLocation)
				: Position(0, 0);
		}
		else
		{
			// offset refers to another file; convert against that file
			pos = positionInFile(context, completion.symbolFilePath,
				completion.symbolLocation);
		}
		Location location;
		location.uri = completion.symbolFilePath == "stdin"
			? params["textDocument"]["uri"].str
			: pathToUri(completion.symbolFilePath);
		location.range = Range(pos, pos);
		locations ~= location.toJson();
	}
	return JSONValue(locations);
}

/**
 * Handles `textDocument/signatureHelp`.
 */
JSONValue handleSignatureHelp(ref ServerContext context, JSONValue params)
{
	auto request = buildRequest(context, params);
	auto response = complete(request, *context.cache);

	if (response.completionType != CompletionType.calltips)
		return JSONValue(null);

	return signatureHelpFromResponse(response).toJson();
}

/**
 * Converts a calltip response to a `SignatureHelp`.
 */
private SignatureHelp signatureHelpFromResponse(AutocompleteResponse response)
{
	SignatureHelp help;
	foreach (completion; response.completions)
	{
		SignatureInformation sig;
		sig.label = completion.definition;
		help.signatures ~= sig;
	}
	help.activeSignature = 0;
	help.activeParameter = 0;
	return help;
}

/**
 * Handles `textDocument/inlayHint`.
 */
JSONValue handleInlayHint(ref ServerContext context, JSONValue params)
{
	// inlayHint params carry a `range`, not a `position`, so build the
	// request manually instead of via buildRequest (which requires position)
	auto textDocument = params["textDocument"];
	string uri = textDocument["uri"].str;
	auto doc = context.documents.get(uri);
	enforceDoc(doc, uri);

	AutocompleteRequest request;
	request.fileName = uriToPath(uri);
	request.sourceCode = cast(ubyte[]) doc.text.dup;
	// inlay hints are computed for the whole document; the range is ignored
	request.cursorPosition = 0;
	auto response = getInlayHints(request, *context.cache);

	if (response.completions.empty)
		return JSONValue(null);

	JSONValue[] hints;
	foreach (completion; response.completions)
	{
		InlayHint hint;
		hint.position = completion.symbolFilePath == "stdin"
			? context.converter.toPosition(*doc, completion.symbolLocation)
			: positionInFile(context, completion.symbolFilePath,
				completion.symbolLocation);
		// Skip internal placeholder names (e.g. "*arr*" for int[]) that
		// dsymbol uses to model arrays, pointers and associative arrays.
		// They appear embedded in labels like "->*arr*". Also skip empty
		// labels.
		if (!completion.identifier.length
			|| completion.identifier.canFind('*'))
			continue;
		hint.label = completion.identifier;
		hint.kind = 1; // Type
		hints ~= hint.toJson();
	}
	return JSONValue(hints);
}

/**
 * Handles `textDocument/documentSymbol`.
 */
JSONValue handleDocumentSymbol(ref ServerContext context, JSONValue params)
{
	import dparse.lexer : LexerConfig, StringCache, getTokensForParser,
		optimalBucketCount;
	import dparse.rollback_allocator : RollbackAllocator;
	import dsymbol.conversion : generateAutocompleteTrees;
	import dsymbol.string_interning : internString;

	auto textDocument = params["textDocument"];
	string uri = textDocument["uri"].str;
	auto doc = context.documents.get(uri);
	enforceDoc(doc, uri);

	LexerConfig config;
	config.fileName = "";
	// clampedBucketCount guards against the empty-document crash
	auto cache = StringCache(clampedBucketCount(doc.text.length));
	auto tokenArray = getTokensForParser(cast(ubyte[]) doc.text, config, &cache);
	RollbackAllocator rba;
	auto pair = generateAutocompleteTrees(tokenArray, &rba, -1, *context.cache);
	scope (exit) pair.destroy();

	HashSet!size_t visited;
	JSONValue[] symbols;
	foreach (symbol; pair.scope_.symbols)
	{
		if (symbol.name == IMPORT_SYMBOL_NAME)
			continue;
		// only symbols declared in this document, not builtins or imports
		if (symbol.symbolFile != "stdin")
			continue;
		symbols ~= documentSymbolFor(context, *doc, symbol, visited).toJson();
	}
	return symbols.length ? JSONValue(symbols) : JSONValue(null);
}

/**
 * Builds a `DocumentSymbol` (with nested children) for a DSymbol.
 */
private DocumentSymbol documentSymbolFor(ref ServerContext context,
	in TextDocument doc, DSymbol* symbol, ref HashSet!size_t visited)
{
	DocumentSymbol result;
	result.name = symbol.name.idup;
	result.kind = toCompletionItemKind(symbol.kind);
	result.detail = symbol.formatType;
	Position pos = context.converter.toPosition(doc, symbol.location);
	result.range = Range(pos, pos);
	result.selectionRange = Range(pos, pos);

	if (visited.contains(cast(size_t) symbol))
		return result;
	visited.insert(cast(size_t) symbol);

	foreach (part; symbol.opSlice())
	{
		if (part.name == IMPORT_SYMBOL_NAME || part.name == CONSTRUCTOR_SYMBOL_NAME
			|| part.name == DESTRUCTOR_SYMBOL_NAME || part.name == UNITTEST_SYMBOL_NAME)
			continue;
		if (!isPublicCompletionKind(part.kind))
			continue;
		result.children ~= documentSymbolFor(context, doc, part, visited);
	}
	return result;
}
