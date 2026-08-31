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
	DESTRUCTOR_SYMBOL_NAME, UNITTEST_SYMBOL_NAME, ARGPTR_SYMBOL_NAME,
	ARGUMENTS_SYMBOL_NAME;
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
	// workspace's own source directories, dub dependencies from the local
	// package cache, and the local Phobos installation.
	auto detected = detectWorkspaceImportPaths(context.rootUri);
	auto dub = detectDubPackageImportPaths(context.rootUri);
	if (!dub.empty)
		detected ~= dub;
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
 * Resolves the dub dependencies of the workspace project and returns the
 * import directories of each dependency, following transitive
 * dependencies. This is what makes `import erupted;` or `import sdl;`
 * resolve without any client-side configuration.
 *
 * The dependency set is read from dub.selections.json (written by
 * `dub build`/`dub upgrade`) when present, falling back to the
 * dependencies listed in dub.json/dub.sdl. Path dependencies
 * (`"dep": {"path": "..."}`) resolve to directories inside the workspace;
 * registry dependencies resolve into the local package cache
 * (~/.dub/packages).
 */
private string[] detectDubPackageImportPaths(string rootUri)
{
	import std.algorithm : map;
	import std.array : array;
	import std.file : dirEntries, exists, isDir, readText, SpanMode;
	import std.json : parseJSON, JSONType;
	import std.path : baseName, buildPath, expandTilde;

	if (rootUri.empty)
		return [];
	string root = uriToPath(rootUri);
	if (root.empty || !exists(root) || !isDir(root))
		return [];

	// Direct dependencies of the workspace project: name -> path
	// dependency directory (empty for registry dependencies).
	string[string] direct;
	foreach (manifest; ["dub.selections.json", "dub.json", "dub.sdl"])
	{
		string m = buildPath(root, manifest);
		if (!exists(m))
			continue;
		if (manifest.endsWith(".json"))
		{
			auto json = parseJSON(readText(m));
			JSONValue deps;
			if ("versions" in json)
				deps = json["versions"]; // dub.selections.json
			else if ("dependencies" in json)
				deps = json["dependencies"]; // dub.json
			if (deps.type == JSONType.object)
			{
				foreach (name, ref version_; deps.object)
				{
					string pathDep;
					if (version_.type == JSONType.object
						&& "path" in version_
						&& version_["path"].type == JSONType.string)
						pathDep = buildPath(root, version_["path"].str);
					direct[name] = pathDep;
				}
				break;
			}
		}
		else
		{
			// dub.sdl: dependency lines look like
			//   dependency "name" optional="true" ...
			foreach (line; readText(m).splitter('\n'))
			{
				auto trimmed = line.strip;
				if (!trimmed.startsWith("dependency"))
					continue;
				auto fields = trimmed.splitter('"').array;
				if (fields.length >= 2)
					direct[fields[1]] = "";
			}
			break;
		}
	}
	if (direct.empty)
		return [];

	// Walk the dependency graph. Registry packages are looked up in the
	// package cache; path packages are directories in the workspace.
	immutable cacheDir = expandTilde("~/.dub/packages");
	immutable cacheExists = exists(cacheDir) && isDir(cacheDir);

	string[] result;
	bool[string] visited;
	string[] queue = direct.keys;
	while (!queue.empty)
	{
		string name = queue[0];
		queue = queue[1 .. $];
		if (name in visited)
			continue;
		visited[name] = true;

		// Resolve the package root: a path dependency, or a cached
		// registry package (~/.dub/packages/<name>/<version>/<name>/).
		string pkgRoot;
		if (auto p = name in direct)
			if (!(*p).empty && exists(*p) && isDir(*p))
				pkgRoot = *p;
		if (pkgRoot.empty && cacheExists)
		{
			string pkgDir = buildPath(cacheDir, name);
			if (exists(pkgDir) && isDir(pkgDir))
			{
				string[] versions = dirEntries(pkgDir, SpanMode.shallow)
					.filter!(a => a.isDir).map!(a => a.name).array;
				if (!versions.empty)
				{
					// Prefer the version dub selected, if recorded;
					// otherwise the newest (lexicographically greatest).
					string chosen;
					if (auto v = name in direct)
						foreach (ver; versions)
							if (baseName(ver) == *v)
								chosen = ver;
					if (chosen.empty)
					{
						sort!((a, b) => a > b)(versions);
						chosen = versions[0];
					}
					pkgRoot = buildPath(chosen, name);
					if (!exists(pkgRoot) || !isDir(pkgRoot))
						pkgRoot = chosen;
				}
			}
		}
		if (pkgRoot.empty)
			continue;

		// Import directories: manifest importPaths, else the standard
		// source/ src/ layout.
		string[] importDirs;
		foreach (manifest; ["dub.json", "dub.sdl"])
		{
			string m = buildPath(pkgRoot, manifest);
			if (!exists(m) || !manifest.endsWith(".json"))
				continue;
			auto json = parseJSON(readText(m));
			if ("importPaths" in json
				&& json["importPaths"].type == JSONType.array)
			{
				foreach (p; json["importPaths"].array)
					if (p.type == JSONType.string)
						importDirs ~= buildPath(pkgRoot, p.str);
			}
			break;
		}
		if (importDirs.empty)
		{
			foreach (dir; ["source", "src", "import"])
			{
				string p = buildPath(pkgRoot, dir);
				if (exists(p) && isDir(p))
					importDirs ~= p;
			}
		}
		foreach (d; importDirs)
			if (exists(d) && isDir(d) && !result.canFind(d))
				result ~= d;

		// Follow transitive dependencies from the package's own manifest.
		foreach (manifest; ["dub.json", "dub.sdl"])
		{
			string m = buildPath(pkgRoot, manifest);
			if (!exists(m))
				continue;
			if (manifest.endsWith(".json"))
			{
				auto json = parseJSON(readText(m));
				if ("dependencies" in json
					&& json["dependencies"].type == JSONType.object)
				{
					foreach (dep, ref spec; json["dependencies"].object)
					{
						if (dep in visited)
							continue;
						if (spec.type == JSONType.object
							&& "path" in spec
							&& spec["path"].type == JSONType.string)
							direct[dep] = buildPath(pkgRoot, spec["path"].str);
						queue ~= dep;
					}
				}
			}
			else
			{
				foreach (line; readText(m).splitter('\n'))
				{
					auto trimmed = line.strip;
					if (!trimmed.startsWith("dependency"))
						continue;
					auto fields = trimmed.splitter('"').array;
					if (fields.length >= 2 && fields[1] !in visited)
						queue ~= fields[1];
				}
			}
			break;
		}
	}
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
		size_t activeParameter = countParametersBeforeCursor(
			cast(char[]) request.sourceCode[0 .. request.cursorPosition]);
		return signatureHelpFromResponse(response, 0, activeParameter).toJson();
	}

	CompletionList list;
	list.isIncomplete = false;
	// Bundle overloads of the same name into a single item (like clangd
	// does for C++ template overloads): "destroy" with 5 template
	// constraints shows once, with the overload count in the detail.
	// The completion engine ranks constraint-matching overloads first, so
	// the first overload seen per name is the most plausible one and its
	// signature is used as the detail.
	CompletionItem[] bundled;
	string[] bundledNames;
	size_t[] bundledCounts;
	foreach (completion; response.completions)
	{
		CompletionItem item;
		item.label = completion.identifier;
		item.kind = toCompletionItemKind(cast(CompletionKind) completion.kind);
		item.detail = completion.typeOf;
		item.documentation = completion.documentation;

		bool merged = false;
		foreach (i, ref existing; bundled)
		{
			if (existing.label == item.label && existing.kind == item.kind)
			{
				bundledCounts[i]++;
				merged = true;
				break;
			}
		}
		if (!merged)
		{
			bundled ~= item;
			bundledNames ~= item.label;
			bundledCounts ~= 1;
		}
	}
	foreach (i, ref item; bundled)
	{
		if (bundledCounts[i] > 1)
			item.detail = item.detail.length
				? item.detail ~ " (+" ~ bundledCounts[i].to!string ~ " overloads)"
				: bundledCounts[i].to!string ~ " overloads";
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
		Position pos = positionInFile(context,
			response.symbolFilePath, response.symbolLocation);
		location.range = Range(pos, pos);
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

	// The parameter the cursor is currently in, counted from the source text
	// (commas at paren depth 0 relative to the call's opening paren).
	size_t activeParameter = countParametersBeforeCursor(
		cast(char[]) request.sourceCode[0 .. request.cursorPosition]);

	// On a retrigger the client passes back the previously active signature
	// help (e.g. after the user cycled overloads with up/down keys). Keep the
	// user's selection instead of resetting to the first overload.
	size_t activeSignature = preferredSignature(response, activeParameter);
	if (params.type == JSONType.object && "context" in params
		&& params["context"].type == JSONType.object
		&& "activeSignatureHelp" in params["context"]
		&& params["context"]["activeSignatureHelp"].type == JSONType.object)
	{
		auto previous = params["context"]["activeSignatureHelp"];
		if ("activeSignature" in previous
			&& previous["activeSignature"].type == JSONType.integer)
		{
			immutable selected = cast(size_t) previous["activeSignature"].integer;
			if (selected < response.completions.length)
				activeSignature = selected;
		}
	}

	return signatureHelpFromResponse(response, activeSignature, activeParameter)
		.toJson();
}

/**
 * Picks the initially shown overload: the first one that actually has a
 * parameter at the cursor's index (e.g. with the cursor in the 2nd argument,
 * a 2-parameter overload is preferred over a 1-parameter one). Falls back
 * to the first overload when none matches.
 */
private size_t preferredSignature(AutocompleteResponse response,
	size_t activeParameter)
{
	// The completion engine already ranks constraint-matching overloads
	// first, so the first overload with a parameter at the cursor's index is
	// both arity- and constraint-plausible.
	foreach (i, completion; response.completions)
	{
		auto ranges = parameterLabelRanges(completion.definition);
		if (ranges.length > activeParameter)
			return i;
	}
	return 0;
}

/**
 * Counts how many call arguments the cursor has passed: the number of
 * top-level commas between the innermost unclosed `(` (or `[`) before the
 * cursor and the cursor itself.
 */
private size_t countParametersBeforeCursor(in char[] source)
{
	if (source.empty)
		return 0;

	// Scan backwards for the innermost unclosed open paren/bracket.
	int depth = 0;
	size_t open = size_t.max;
	for (size_t i = source.length; i-- > 0;)
	{
		immutable c = source[i];
		if (c == ')')
			depth++;
		else if (c == '(')
		{
			if (depth == 0)
			{
				open = i;
				break;
			}
			depth--;
		}
		else if (c == ']')
			depth++;
		else if (c == '[')
		{
			if (depth == 0)
			{
				open = i;
				break;
			}
			depth--;
		}
	}
	if (open == size_t.max)
		return 0;

	// Count commas at depth 0 relative to that paren. Comments and string
	// literals must not contribute commas.
	size_t commas = 0;
	int inner = 0;
	for (size_t i = open + 1; i < source.length; i++)
	{
		immutable c = source[i];
		if (c == '(' || c == '[' || c == '{')
			inner++;
		else if (c == ')' || c == ']' || c == '}')
			inner--;
		else if (c == ',' && inner == 0)
			commas++;
	}
	return commas;
}

/**
 * Converts a calltip response to a `SignatureHelp`.
 *
 * Params:
 *     response = the calltip response from the autocompletion engine
 *     activeSignature = the initially selected overload
 *     activeParameter = the parameter the cursor is in
 */
private SignatureHelp signatureHelpFromResponse(AutocompleteResponse response,
	size_t activeSignature, size_t activeParameter)
{
	SignatureHelp help;
	foreach (completion; response.completions)
	{
		SignatureInformation sig;
		sig.label = completion.definition;
		// Parameter labels with offsets into `label` let the client highlight
		// the active argument; without them the widget can't show which
		// parameter is being typed.
		foreach (range; parameterLabelRanges(sig.label))
		{
			ParameterInformation param;
			param.labelStart = range[0];
			param.labelEnd = range[1];
			sig.parameters ~= param;
		}
		help.signatures ~= sig;
	}
	help.activeSignature = activeSignature;
	help.activeParameter = activeParameter;
	return help;
}

/**
 * Splits a calltip label like `void foo(int a, string s)` into the
 * `[start, end)` offsets of each parameter inside the outermost parentheses.
 * Template parameter lists (`foo!(T)(T a)`) contribute only the function
 * parameter list.
 */
private size_t[][] parameterLabelRanges(string label)
{
	size_t[][] ranges;
	if (label.empty)
		return ranges;

	// Find the last top-level paren pair: skips template parens `!(...)`.
	size_t open = label.lastIndexOf('(');
	if (open == size_t.max || open + 1 >= label.length)
		return ranges;
	size_t close = label.lastIndexOf(')');
	if (close == size_t.max || close <= open)
		return ranges;

	size_t start = open + 1;
	size_t depth = 0;
	for (size_t i = open + 1; i < close; i++)
	{
		immutable c = label[i];
		if (c == '(' || c == '[' || c == '{')
			depth++;
		else if (c == ')' || c == ']' || c == '}')
			depth--;
		else if (c == ',' && depth == 0)
		{
			ranges ~= trimRange(label, start, i);
			start = i + 1;
		}
	}
	// trailing parameter (or the only one) if the parens aren't empty
	if (start < close)
		ranges ~= trimRange(label, start, close);
	return ranges;
}

/**
 * Shrinks a `[start, end)` range to exclude surrounding whitespace.
 */
private size_t[] trimRange(string label, size_t start, size_t end)
{
	while (start < end && (label[start] == ' ' || label[start] == '\t'))
		start++;
	while (end > start && (label[end - 1] == ' ' || label[end - 1] == '\t'))
		end--;
	return [start, end];
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
		// Skip internal placeholder names (e.g. "*arr*" for int[]) that
		// dsymbol uses to model arrays, pointers and associative arrays.
		// They appear embedded in labels like "->*arr*". Also skip empty
		// labels.
		if (!completion.identifier.length
			|| completion.identifier.canFind('*'))
			continue;
		// A stale or bogus offset (e.g. from an incomplete parse while the
		// user is typing) must not fail the whole request — skip the hint.
		try
		{
			hint.position = completion.symbolFilePath == "stdin"
				? context.converter.toPosition(*doc, completion.symbolLocation)
				: positionInFile(context, completion.symbolFilePath,
					completion.symbolLocation);
		}
		catch (Exception e)
		{
			warningf("Skipping inlay hint with bad offset %s: %s",
				completion.symbolLocation, e.msg);
			continue;
		}
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
	// A bogus offset (e.g. size_t.max on synthetic varargs symbols, or a
	// stale location from an incomplete parse) must not fail the whole
	// request — clamp it to the document end.
	Position pos;
	try
		pos = context.converter.toPosition(doc, symbol.location);
	catch (Exception e)
	{
		warningf("Skipping document symbol '%s' with bad offset %s: %s",
			symbol.name, symbol.location, e.msg);
		return result;
	}
	result.range = Range(pos, pos);
	result.selectionRange = Range(pos, pos);

	if (visited.contains(cast(size_t) symbol))
		return result;
	visited.insert(cast(size_t) symbol);

	foreach (part; symbol.opSlice())
	{
		if (part.name == IMPORT_SYMBOL_NAME || part.name == CONSTRUCTOR_SYMBOL_NAME
			|| part.name == DESTRUCTOR_SYMBOL_NAME || part.name == UNITTEST_SYMBOL_NAME
			|| part.name == ARGPTR_SYMBOL_NAME || part.name == ARGUMENTS_SYMBOL_NAME)
			continue;
		// Unnamed symbols (e.g. anonymous function parameters like
		// `void f(in void*)`) have no name to show in an outline; VS Code
		// rejects them with "name must not be falsy".
		if (part.name is null || !part.name.length)
			continue;
		if (!isPublicCompletionKind(part.kind))
			continue;
		result.children ~= documentSymbolFor(context, doc, part, visited);
	}
	return result;
}
