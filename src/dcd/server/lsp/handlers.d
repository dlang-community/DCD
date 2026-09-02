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
		case "textDocument/prepareRename":
			return HandlerResult(handlePrepareRename(context, params));
		case "textDocument/rename":
			return HandlerResult(handleRename(context, params));
		case "textDocument/signatureHelp":
			return HandlerResult(handleSignatureHelp(context, params));
		case "textDocument/inlayHint":
			return HandlerResult(handleInlayHint(context, params));
		case "textDocument/documentSymbol":
			return HandlerResult(handleDocumentSymbol(context, params));
		case "workspace/willRenameFiles":
			return HandlerResult(handleWillRenameFiles(context, params));
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
	capabilities["renameProvider"] = parseJSON(`{"prepareProvider": true}`);
	capabilities["documentSymbolProvider"] = JSONValue(true);
	capabilities["inlayHintProvider"] = JSONValue(true);
	// File rename support: when the user moves/renames a file in the editor,
	// the client asks (before the rename happens) for edits that update the
	// file's module declaration and every import of the old module name.
	// The filters select which operations the client forwards: .d/.di files
	// and directories (a directory move changes the module names of every
	// file inside it).
	capabilities["workspace"] = parseJSON(`{
		"fileOperations": {
			"willRename": {
				"filters": [
					{"pattern": {"glob": "**/*.d"}},
					{"pattern": {"glob": "**/*.di"}},
					{"pattern": {"glob": "**", "matches": "folder"}}
				]
			}
		}
	}`);
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

	// Warm the module cache for this document's imports right away. DCD
	// resolves imports lazily inside whichever request first needs them,
	// which stalls that request by the parse time of the whole import
	// closure (std.stdio plus its Phobos dependencies costs ~800ms). Doing
	// it here moves that cost to document-open time, while the editor is
	// still settling, instead of the user's first completion or hover.
	// This is single-threaded on purpose: messages arriving during the
	// warmup simply queue in the pipe and are handled in order afterwards.
	if (languageId.empty || languageId == "d")
	{
		try
			warmupDocument(context, text);
		catch (Exception e)
			warningf("Warmup failed for %s: %s", uri, e.msg);
		// Record the document's current imports as warmed so that later
		// didChanges only warm imports added while editing.
		warmNewImports(context, uri);
	}
}

/**
 * Pre-parses a document and resolves its import closure into the module
 * cache.
 *
 * This is the same work the first semantic request would otherwise do
 * lazily (`generateAutocompleteTrees` → second pass →
 * `ModuleCache.cacheModule`), so every subsequent request starts with a
 * warm cache. Already-cached modules are skipped by modification time, so
 * repeated didOpens are cheap.
 */
private void warmupDocument(ref ServerContext context, string text)
{
	import dparse.lexer : LexerConfig, StringCache, getTokensForParser;
	import dparse.rollback_allocator : RollbackAllocator;
	import dsymbol.conversion : generateAutocompleteTrees;
	import std.datetime.stopwatch : StopWatch, AutoStart;

	auto sw = StopWatch(AutoStart.yes);
	LexerConfig config;
	config.fileName = "";
	// clampedBucketCount guards against the empty-document crash
	auto stringCache = StringCache(clampedBucketCount(text.length));
	auto tokens = getTokensForParser(cast(ubyte[]) text, config, &stringCache);
	RollbackAllocator rba;
	auto pair = generateAutocompleteTrees(tokens, &rba, -1, *context.cache);
	scope (exit) pair.destroy();
	infof("Warmup: indexed document and imports in %s ms",
		sw.peek().total!"msecs");
}

/**
 * Scans tokenized source for import declarations and returns the imported
 * module paths in DCD's internal "a/b/c" form (dirSeparator-joined, the
 * format `resolveImportLocation` expects — NOT dot-separated).
 *
 * This is a cheap token-level scan (no parsing) used to detect imports
 * added while editing. It covers the forms that affect module resolution:
 * plain chains (`import a.b;`), import lists (`import a, b;`), renamed
 * imports (`import io = a.b;` — the chain is what resolves) and selective
 * imports (`import a.b : x;` — the module, not the binds, needs caching).
 * Import expressions (`import("file")`) are not declarations and are
 * skipped. A chain is only reported once it is grammatically finished
 * (`;`, `:` or `,` follows): a partial `import std.` typed mid-statement
 * must not resolve to the std package module and warm half of Phobos. A
 * form the scan misses simply falls back to DCD's normal lazy resolution,
 * so it costs the old first-request stall, never correctness.
 */
private string[] scanImportPaths(T)(T tokens)
{
	import dparse.lexer : tok;
	import std.path : dirSeparator;

	string[] result;
	size_t i = 0;
	while (i < tokens.length)
	{
		if (tokens[i].type != tok!"import")
		{
			i++;
			continue;
		}
		// import("expr") is an import expression, not a declaration
		if (i + 1 < tokens.length && tokens[i + 1].type == tok!"(")
		{
			i++;
			continue;
		}
		i++;
		// ImportList: SingleImport ("," SingleImport)* (":" ImportBinds)?
		while (true)
		{
			// renamed import: Identifier "=" IdentifierChain
			if (i + 1 < tokens.length && tokens[i].type == tok!"identifier"
				&& tokens[i + 1].type == tok!"=")
				i += 2;
			string[] chain;
			while (i < tokens.length && tokens[i].type == tok!"identifier")
			{
				chain ~= tokens[i].text;
				i++;
				if (i < tokens.length && tokens[i].type == tok!".")
				{
					i++;
					continue;
				}
				break;
			}
			if (!chain.empty && i < tokens.length
				&& (tokens[i].type == tok!";" || tokens[i].type == tok!":"
					|| tokens[i].type == tok!","))
				result ~= chain.join(dirSeparator);
			// a comma starts the next SingleImport of the list
			if (i < tokens.length && tokens[i].type == tok!",")
			{
				i++;
				continue;
			}
			break; // ";" / ":" / malformed: done with this declaration
		}
	}
	return result;
}

unittest
{
	import dparse.lexer : LexerConfig, StringCache, getTokensForParser;
	import std.path : dirSeparator;

	string[] importsOf(string text)
	{
		LexerConfig config;
		auto cache = StringCache(clampedBucketCount(text.length));
		auto tokens = getTokensForParser(cast(ubyte[]) text, config, &cache);
		return scanImportPaths(tokens);
	}

	assert(importsOf("import std.stdio;") == ["std" ~ dirSeparator ~ "stdio"]);
	assert(importsOf("import std.stdio, std.conv;")
		== ["std" ~ dirSeparator ~ "stdio", "std" ~ dirSeparator ~ "conv"]);
	assert(importsOf("import io = std.stdio;")
		== ["std" ~ dirSeparator ~ "stdio"]);
	assert(importsOf("import std.stdio : writeln, writef;")
		== ["std" ~ dirSeparator ~ "stdio"]);
	assert(importsOf("static import std.stdio;")
		== ["std" ~ dirSeparator ~ "stdio"]);
	assert(importsOf("void main() { import std.regex; }")
		== ["std" ~ dirSeparator ~ "regex"]);
	// strings, comments and import expressions are not declarations
	assert(importsOf(`auto s = "import foo.bar;";`) == []);
	assert(importsOf("// import foo.bar;\nint x;") == []);
	assert(importsOf(`auto m = import("config.txt");`) == []);
	// incomplete while typing: no warm until the chain is finished
	assert(importsOf("import std.") == []);
	assert(importsOf("import std.stdio") == []);
	assert(importsOf("import std.stdio :")
		== ["std" ~ dirSeparator ~ "stdio"]);
	assert(importsOf("import") == []);
	assert(importsOf("") == []);
}

/**
 * Warms the module cache for imports that appeared since the last check.
 *
 * `handleDidOpen` warms a newly opened document's whole import closure
 * with a full parse; this covers imports ADDED while editing, which would
 * otherwise stall the first request that needs them by the parse time of
 * the new module's dependency closure. Only the delta is warmed: imports
 * already recorded on the document are skipped, and only imports that
 * resolve are recorded, so an import that is still being typed (or whose
 * module does not exist yet) is retried on the next change. Like the
 * didOpen warmup this is single-threaded on purpose.
 */
private void warmNewImports(ref ServerContext context, string uri)
{
	import dparse.lexer : LexerConfig, StringCache, getTokensForParser;
	import std.datetime.stopwatch : StopWatch, AutoStart;

	auto doc = context.documents.get(uri);
	if (doc is null)
		return;
	// Only D documents (same check as handleDidOpen's warmup)
	if (!doc.languageId.empty && doc.languageId != "d")
		return;
	// Cheap pre-check: no "import" substring means no import declarations.
	if (!doc.text.canFind("import"))
		return;

	LexerConfig config;
	config.fileName = "";
	// clampedBucketCount guards against the empty-document crash
	auto stringCache = StringCache(clampedBucketCount(doc.text.length));
	auto tokens = getTokensForParser(cast(ubyte[]) doc.text, config, &stringCache);

	string[] fresh;
	foreach (modulePath; scanImportPaths(tokens))
		if (!doc.warmedImports.canFind(modulePath))
			fresh ~= modulePath;
	if (fresh.empty)
		return;

	auto sw = StopWatch(AutoStart.yes);
	size_t warmed;
	foreach (modulePath; fresh)
	{
		// The same resolution the first pass applies to import symbols.
		// cacheModule recursively caches the module's own imports, so the
		// whole dependency closure is warmed; already-cached modules are
		// skipped by modification time.
		string location = context.cache.resolveImportLocation(modulePath);
		if (location is null)
			continue;
		try
		{
			if (context.cache.cacheModule(location) !is null)
			{
				doc.warmedImports ~= modulePath;
				warmed++;
			}
		}
		catch (Exception e)
		{
			// One bad module must not abort the rest; it is retried on
			// the next change since it was not recorded.
			warningf("Warmup failed for import %s: %s", modulePath, e.msg);
		}
	}
	if (warmed)
		infof("Warmup: indexed %s new import(s) for %s in %s ms",
			warmed, uri, sw.peek().total!"msecs");
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

	// Warm imports added by this change (see handleDidOpen): a newly typed
	// `import std.regex;` would otherwise stall the first request that
	// needs it by the parse time of its whole dependency closure.
	warmNewImports(context, uri);
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

	// findLocalUse only reports uses within the requesting document: the
	// per-completion symbolFilePath is left empty (only the top-level
	// response carries the declaration's file), so the uses must be
	// converted against the requesting document, never treated as
	// external-file offsets.
	auto doc = context.documents.get(params["textDocument"]["uri"].str);

	// LSP: "Include the declaration of the current symbol." VS Code's
	// "Find All References" sends true by default.
	bool includeDeclaration = true;
	if (params.type == JSONType.object && "context" in params
		&& params["context"].type == JSONType.object
		&& "includeDeclaration" in params["context"]
		&& params["context"]["includeDeclaration"].type == JSONType.false_)
	{
		includeDeclaration = false;
	}

	JSONValue[] locations;

	// The declaration itself. For symbols declared in the requesting
	// document it is already part of the uses list below (the declaration
	// identifier resolves to the same symbol), so only add it separately
	// when it lives in another file.
	if (includeDeclaration && response.symbolFilePath.length
		&& response.symbolFilePath != "stdin")
	{
		Location location;
		location.uri = pathToUri(response.symbolFilePath);
		Position pos = positionInFile(context, response.symbolFilePath,
			response.symbolLocation);
		location.range = Range(pos, pos);
		locations ~= location.toJson();
	}

	foreach (completion; response.completions)
	{
		// Skip the declaration itself when the client asked for uses only.
		// The declaration's offset (in the requesting document) is
		// response.symbolLocation.
		if (!includeDeclaration && response.symbolFilePath == "stdin"
			&& completion.symbolLocation == response.symbolLocation)
		{
			continue;
		}
		Position pos = doc !is null
			? context.converter.toPosition(*doc, completion.symbolLocation)
			: Position(0, 0);
		Location location;
		location.uri = params["textDocument"]["uri"].str;
		location.range = Range(pos, pos);
		locations ~= location.toJson();
	}

	if (locations.empty)
		return JSONValue(null);
	return JSONValue(locations);
}

/**
 * Shared result of a rename lookup: the identifier range at the request
 * position plus every use of the symbol within the workspace.
 */
private struct RenameLookup
{
	/// The identifier token at the request position, if any.
	Range identifierRange;

	/// The identifier's text (needed to compute each edit's end position).
	string identifier;

	/// The file the symbol is declared in (DCD-internal path; "stdin" for
	/// the requesting document).
	string declarationFile;

	/// The byte offset of the declaration in its file.
	size_t declarationOffset;

	/// Uses grouped by file path: (file path, byte offsets). The
	/// requesting document is keyed by its URI; other files by path.
	private string[] _files;
	private size_t[][] _offsets;

	/// True when the fields above are valid.
	bool valid;

	/// Records a use at the given offset in the given file.
	void addUse(string file, size_t offset)
	{
		foreach (i, f; _files)
		{
			if (f == file)
			{
				_offsets[i] ~= offset;
				return;
			}
		}
		_files ~= file;
		_offsets ~= [offset];
	}

	/// The files that contain uses of the symbol.
	auto files() return
	{
		return _files[];
	}

	/// The use offsets recorded for the given file.
	auto offsetsIn(string file)
	{
		foreach (i, f; _files)
			if (f == file)
				return _offsets[i][];
		return (size_t[]).init[0 .. 0];
	}
}

/**
 * Performs the rename lookup shared by prepareRename and rename.
 *
 * The symbol at the request position is identified with `findLocalUse`,
 * which yields the declaration's file and offset. Uses are then searched
 * across the whole workspace: every .d/.di file under the server's import
 * paths is lexed and each same-named identifier is resolved to its symbol
 * to check whether it denotes the same declaration. The identifier range
 * is computed by lexing the requesting document and finding the identifier
 * token containing the request position — this also validates that the
 * cursor is on a renameable identifier and not a keyword, literal or
 * comment.
 */
private RenameLookup lookupRename(ref ServerContext context, JSONValue params)
{
	import dparse.lexer : LexerConfig, StringCache, getTokensForParser, Token, tok;

	RenameLookup result;

	auto request = buildSymbolRequest(context, params);
	auto response = findLocalUse(request, *context.cache);

	if (response.completions.empty)
		return result;

	auto doc = context.documents.get(params["textDocument"]["uri"].str);
	if (doc is null)
		return result;

	// Lex the document to find the identifier token at the request
	// position. buildSymbolRequest already nudged the cursor one byte
	// into a first-character token, so the token containing the (nudged)
	// offset is the one the user clicked on.
	LexerConfig config;
	config.fileName = "";
	// clampedBucketCount guards against the empty-document crash
	auto stringCache = StringCache(clampedBucketCount(doc.text.length));
	auto tokens = getTokensForParser(cast(ubyte[]) doc.text, config, &stringCache);

	Position position = Position.fromJson(params["position"]);
	size_t offset = context.converter.toOffset(*doc, position);

	const(Token)* found;
	foreach (ref t; tokens)
	{
		if (t.type == tok!"identifier"
			&& offset >= t.index && offset < t.index + t.text.length)
		{
			found = &t;
			break;
		}
	}
	if (found is null)
		return result;

	result.identifier = found.text.idup;
	result.identifierRange = Range(
		context.converter.toPosition(*doc, found.index),
		context.converter.toPosition(*doc, found.index + found.text.length));

	// The declaration identifies the symbol across files. For symbols
	// declared in the requesting document findLocalUse reports "stdin";
	// normalize it to the document's path so that uses in OTHER files
	// (which resolve through the cached on-disk module) compare equal.
	string requestUri = params["textDocument"]["uri"].str;
	result.declarationFile = response.symbolFilePath == "stdin"
		? uriToPath(requestUri)
		: response.symbolFilePath;
	result.declarationOffset = response.symbolLocation;

	// Uses within the requesting document (the declaration is part of the
	// uses list when the symbol is declared here).
	foreach (completion; response.completions)
		result.addUse(requestUri, completion.symbolLocation);

	// Uses in other workspace files. Only symbols declared in the
	// requesting document or in a cached module can be tracked; symbols
	// from unresolved modules keep the document-local behavior.
	if (result.declarationFile.length)
		findWorkspaceUses(context, result, requestUri);

	result.valid = true;
	return result;
}

/**
 * A use of the renamed symbol in a workspace file.
 */
private struct WorkspaceUse
{
	/// Absolute path of the file containing the use.
	string path;

	/// Byte offset of the identifier within that file.
	size_t offset;
}

/**
 * Searches all workspace .d/.di files for uses of the symbol declared at
 * `lookup.declarationFile`/`declarationOffset`.
 *
 * Every file under the server's import paths is lexed and each identifier
 * matching the renamed symbol's name is resolved through DCD's symbol
 * machinery (parse + scope lookup); a match counts when it resolves to a
 * symbol declared at the target declaration. This is the same resolution
 * strategy `findLocalUse` applies within a document, extended to the
 * workspace. Files that fail to parse are skipped.
 */
private void findWorkspaceUses(ref ServerContext context,
	ref RenameLookup lookup, string requestUri)
{
	import dparse.lexer : LexerConfig, StringCache, getTokensForParser, Token, tok;
	import dparse.rollback_allocator : RollbackAllocator;
	import dsymbol.conversion : generateAutocompleteTrees, ScopeSymbolPair;
	import dsymbol.utils : getExpression;
	import dcd.server.autocomplete.util : getSymbolsByTokenChain;
	import std.range : assumeSorted;
	import std.file : dirEntries, isFile, readText, SpanMode;
	import std.path : extension;

	// Collect the workspace's .d/.di files. Only the workspace root is
	// scanned — NOT the import paths: they include auto-detected Phobos
	// and dub dependencies (read-only library sources, thousands of files;
	// scanning them makes rename take minutes and edits there could never
	// be applied anyway).
	string[] files;
	void addFile(string path)
	{
		// Paths can overlap (e.g. the workspace root and its source/
		// directory), so deduplicate.
		if (!files.canFind(path))
			files ~= path;
	}
	string root = context.rootUri.empty ? string.init : uriToPath(context.rootUri);
	if (!root.empty)
	{
		if (isFile(root))
		{
			addFile(root);
		}
		else
		{
			try foreach (entry; dirEntries(root, SpanMode.depth))
			{
				if (!isFile(entry.name))
					continue;
				immutable ext = extension(entry.name);
				if (ext != ".d" && ext != ".di")
					continue;
				addFile(entry.name);
			}
			catch (Exception e)
			{
				warningf("Rename scan failed for %s: %s", root, e.msg);
			}
		}
	}

	// The declaration's identity: file + offset. Symbols declared in the
	// requesting document carry the "stdin" marker internally.
	immutable targetFile = lookup.declarationFile;
	immutable targetOffset = lookup.declarationOffset;

	foreach (file; files)
	{
		// The requesting document is handled from its in-memory state.
		if (pathToUri(file) == requestUri)
			continue;

		string source;
		try source = readText(file);
		catch (Exception e)
		{
			warningf("Rename scan failed to read %s: %s", file, e.msg);
			continue;
		}
		if (!source.canFind(lookup.identifier))
			continue;

		LexerConfig config;
		config.fileName = file;
		auto stringCache = StringCache(clampedBucketCount(source.length));
		auto tokens = getTokensForParser(cast(ubyte[]) source, config, &stringCache);

		// Candidate offsets: identifier tokens with the target name.
		size_t[] candidates;
		foreach (ref t; tokens)
		{
			if (t.type == tok!"identifier" && t.text == lookup.identifier)
				candidates ~= t.index;
		}
		if (candidates.empty)
			continue;

		// Resolve each candidate against the file's symbol table.
		// generateAutocompleteTrees hardcodes the module name "stdin", so
		// symbols DECLARED in this scanned file carry symbolFile == "stdin"
		// while the same declaration seen from other files carries the
		// real path. Normalize both sides of the identity check: a symbol
		// from this file's own tree matches the target when the target is
		// either this file's path or "stdin" (the requesting document).
		immutable bool targetIsThisFile = targetFile == file;
		immutable bool targetIsRequestDoc = targetFile == "stdin";
		RollbackAllocator rba;
		ScopeSymbolPair pair = generateAutocompleteTrees(tokens,
			&rba, -1, *context.cache);
		scope(exit) pair.destroy();

		foreach (candidate; candidates)
		{
			// Position the cursor inside the token (DCD's cursor counts
			// bytes before the cursor, so +1 lands inside the identifier).
			auto beforeTokens = assumeSorted(tokens)
				.lowerBound(cast(size_t) (candidate + 1));
			auto expression = getExpression(beforeTokens);
			auto symbols = getSymbolsByTokenChain(pair.scope_, expression,
				candidate + 1, CompletionType.location);
			foreach (symbol; symbols)
			{
				immutable bool symbolFromThisFile = symbol.symbolFile == "stdin";
				immutable bool matches = symbolFromThisFile
					? (targetIsThisFile || targetIsRequestDoc)
					: (symbol.symbolFile == targetFile);
				if (matches && symbol.location == targetOffset)
				{
					lookup.addUse(file, candidate);
					break;
				}
			}
		}
	}
}

/**
 * Handles `textDocument/prepareRename`.
 *
 * Returns the range of the identifier at the given position so the client
 * can highlight it, or null when the element cannot be renamed (cursor not
 * on an identifier, or no symbol found for it).
 */
JSONValue handlePrepareRename(ref ServerContext context, JSONValue params)
{
	auto lookup = lookupRename(context, params);
	if (!lookup.valid)
		return JSONValue(null);

	JSONValue result = parseJSON(`{}`);
	result["range"] = lookup.identifierRange.toJson();
	result["placeholder"] = JSONValue(lookup.identifier);
	return result;
}

/**
 * Handles `textDocument/rename`.
 *
 * Renames the symbol at the given position and returns the edits for every
 * file in the workspace that uses it, grouped into one TextDocumentEdit
 * per file. The client applies the edits with a workspace-wide rename UI.
 */
JSONValue handleRename(ref ServerContext context, JSONValue params)
{
	auto lookup = lookupRename(context, params);
	if (!lookup.valid)
		throw new Exception("The element can't be renamed");

	string newName;
	if (params.type == JSONType.object && "newName" in params
		&& params["newName"].type == JSONType.string)
	{
		newName = params["newName"].str;
	}
	if (newName.empty)
		throw new Exception("Missing newName parameter");

	// Reject names that are not valid D identifiers or that collide with
	// keywords — the client would otherwise apply edits that break the code.
	if (!isValidDIdentifier(newName))
		throw new Exception("Invalid identifier: " ~ newName);

	// Build one TextDocumentEdit per file containing uses. The requesting
	// document is keyed by its URI (the client resolves it to the open
	// buffer); other files are keyed by their file URI.
	JSONValue[] documentChanges;
	foreach (file; lookup.files)
	{
		// The requesting document's edits are computed against the
		// in-memory document; other files against their on-disk content.
		TextDocument* doc = context.documents.get(file);
		if (doc is null)
		{
			// file is a path here; convert offsets against the file text
			auto fileDoc = documentForFile(context, file);
			if (fileDoc is null)
				continue;
			JSONValue[] edits;
			foreach (offset; lookup.offsetsIn(file))
			{
				TextEdit edit;
				edit.range = Range(
					context.converter.toPosition(*fileDoc, offset),
					context.converter.toPosition(*fileDoc,
						offset + lookup.identifier.length));
				edit.newText = newName;
				edits ~= edit.toJson();
			}
			documentChanges ~= textDocumentEdit(pathToUri(file), edits);
		}
		else
		{
			JSONValue[] edits;
			foreach (offset; lookup.offsetsIn(file))
			{
				TextEdit edit;
				edit.range = Range(
					context.converter.toPosition(*doc, offset),
					context.converter.toPosition(*doc,
						offset + lookup.identifier.length));
				edit.newText = newName;
				edits ~= edit.toJson();
			}
			documentChanges ~= textDocumentEdit(file, edits);
		}
	}

	JSONValue result = parseJSON(`{}`);
	result["documentChanges"] = JSONValue(documentChanges);
	return result;
}

/**
 * Builds a TextDocumentEdit JSON value.
 *
 * The textDocument identifier is an OptionalVersionedTextDocumentIdentifier:
 * the client libraries (vscode-languageserver-protocol) require `version`
 * to be null or an integer — echoing a request's {uri} without a version
 * field makes TextDocumentEdit.is() fail and the edit gets rejected with
 * "Unknown workspace edit change received".
 */
private JSONValue textDocumentEdit(string uri, JSONValue[] edits)
{
	JSONValue documentChange = parseJSON(`{}`);
	JSONValue textDocument = parseJSON(`{}`);
	textDocument["uri"] = JSONValue(uri);
	textDocument["version"] = JSONValue(null);
	documentChange["textDocument"] = textDocument;
	documentChange["edits"] = JSONValue(edits);
	return documentChange;
}

/**
 * Reads a file from disk into a temporary TextDocument for offset/position
 * conversion. Returns null when the file cannot be read.
 */
private TextDocument* documentForFile(ref ServerContext context, string path)
{
	import std.file : readText;

	TextDocument* doc = new TextDocument;
	try doc.text = readText(path);
	catch (Exception e)
	{
		warningf("Rename failed to read %s: %s", path, e.msg);
		return null;
	}
	doc.reindex();
	return doc;
}

/**
 * Returns true when the given string is a valid D identifier: non-empty,
 * starting with a letter or underscore, containing only identifier
 * characters, and not a D keyword.
 */
private bool isValidDIdentifier(string name)
{
	import dparse.lexer : LexerConfig, StringCache, getTokensForParser, tok;

	if (name.empty)
		return false;
	if (!isIdentChar(cast(ubyte) name[0])
		|| (name[0] >= '0' && name[0] <= '9'))
		return false;
	foreach (c; name)
	{
		if (!isIdentChar(cast(ubyte) c))
			return false;
	}

	// Lex the name: if it comes back as a single identifier token it is not
	// a keyword; keywords lex to their keyword token type instead.
	LexerConfig config;
	config.fileName = "";
	// clampedBucketCount guards against the empty-document crash
	auto stringCache = StringCache(clampedBucketCount(name.length));
	auto tokens = getTokensForParser(cast(ubyte[]) name, config, &stringCache);
	if (tokens.length != 1 || tokens[0].type != tok!"identifier")
		return false;
	return true;
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

/**
 * A use of a module name: the identifier chain of a `module` declaration or
 * of an import declaration, with the byte range it occupies.
 */
private struct ModuleNameUse
{
	/// The dotted segments of the module name, e.g. ["std", "stdio"].
	string[] segments;

	/// Byte offset of the first identifier.
	size_t start;

	/// Byte offset one past the last identifier. Equal to `start` when no
	/// identifier chain follows (invalid use).
	size_t end;
}

/**
 * Scans tokenized source for module name uses: the identifier chains of
 * `module` declarations and of import declarations (plain, renamed and
 * selective imports, and import lists). Import expressions
 * (`import("file")`) are not declarations and are skipped. Import chains
 * are only reported once they are grammatically finished (`;`, `:` or `,`
 * follows), so a partial `import std.` typed mid-statement is not mistaken
 * for a module reference.
 */
private ModuleNameUse[] scanModuleNameUses(T)(T tokens)
{
	import dparse.lexer : tok;

	ModuleNameUse[] result;
	size_t i = 0;
	while (i < tokens.length)
	{
		immutable isModuleDecl = tokens[i].type == tok!"module";
		immutable isImportDecl = tokens[i].type == tok!"import";
		if (!isModuleDecl && !isImportDecl)
		{
			i++;
			continue;
		}
		// import("expr") is an import expression, not a declaration
		if (isImportDecl && i + 1 < tokens.length && tokens[i + 1].type == tok!"(")
		{
			i++;
			continue;
		}
		i++;
		if (isModuleDecl)
		{
			auto use = scanIdentifierChain(tokens, i);
			if (use.start != use.end)
				result ~= use;
			continue;
		}
		// ImportList: SingleImport ("," SingleImport)* (":" ImportBinds)?
		while (true)
		{
			// renamed import: Identifier "=" IdentifierChain — the chain
			// after the "=" is what resolves
			if (i + 1 < tokens.length && tokens[i].type == tok!"identifier"
				&& tokens[i + 1].type == tok!"=")
				i += 2;
			auto use = scanIdentifierChain(tokens, i);
			if (use.start != use.end && i < tokens.length
				&& (tokens[i].type == tok!";" || tokens[i].type == tok!":"
					|| tokens[i].type == tok!","))
			{
				result ~= use;
			}
			// a comma starts the next SingleImport of the list
			if (i < tokens.length && tokens[i].type == tok!",")
			{
				i++;
				continue;
			}
			break; // ";" / ":" / malformed: done with this declaration
		}
	}
	return result;
}

/**
 * Scans a dotted identifier chain starting at token index `i`, advancing
 * `i` past it. Returns the chain with its byte range; `start == end` when
 * no identifier follows.
 */
private ModuleNameUse scanIdentifierChain(T)(T tokens, ref size_t i)
{
	import dparse.lexer : tok;

	ModuleNameUse use;
	if (i >= tokens.length || tokens[i].type != tok!"identifier")
		return use;
	use.start = tokens[i].index;
	while (i < tokens.length && tokens[i].type == tok!"identifier")
	{
		use.segments ~= tokens[i].text.idup;
		use.end = tokens[i].index + tokens[i].text.length;
		i++;
		if (i < tokens.length && tokens[i].type == tok!".")
		{
			i++;
			continue;
		}
		break;
	}
	return use;
}

unittest
{
	import dparse.lexer : LexerConfig, StringCache, getTokensForParser;

	ModuleNameUse[] usesOf(string text)
	{
		LexerConfig config;
		auto cache = StringCache(clampedBucketCount(text.length));
		auto tokens = getTokensForParser(cast(ubyte[]) text, config, &cache);
		return scanModuleNameUses(tokens);
	}

	// module declarations and plain/renamed/selective imports, lists,
	// static imports
	auto uses = usesOf("module a.b;\nimport a.b;\nimport io = a.b;\n"
		~ "import a.b : x;\nimport a.b, c.d;\nstatic import a.b;\nvoid f(){}");
	assert(uses.length == 7);
	foreach (use; uses)
		assert(use.segments == ["a", "b"] || use.segments == ["c", "d"],
			"unexpected segments: " ~ use.segments.join("."));
	// "module a.b;" — the chain a.b spans bytes 7..10
	assert(uses[0].start == 7 && uses[0].end == 10);

	// strings, comments and import expressions are not declarations
	assert(usesOf(`auto s = "import foo.bar;";`).length == 0);
	assert(usesOf("// import foo.bar;\nint x;").length == 0);
	assert(usesOf(`auto m = import("config.txt");`).length == 0);

	// incomplete while typing: no match until the chain is finished
	assert(usesOf("import std.").length == 0);
	assert(usesOf("import std.stdio").length == 0);
	assert(usesOf("import std.stdio :").length == 1);
	assert(usesOf("import").length == 0);
	assert(usesOf("").length == 0);
}

/**
 * Collects every .d/.di file under the workspace root, deduplicated.
 *
 * Only the workspace root is scanned — NOT the import paths: they include
 * auto-detected Phobos and dub dependencies (read-only library sources,
 * thousands of files; scanning them makes rename take minutes and edits
 * there could never be applied anyway).
 */
private string[] collectWorkspaceDFiles(ref ServerContext context)
{
	import std.file : dirEntries, isFile, SpanMode;
	import std.path : extension;

	string[] files;
	void addFile(string path)
	{
		// Paths can overlap (e.g. the workspace root and its source/
		// directory), so deduplicate.
		if (!files.canFind(path))
			files ~= path;
	}
	string root = context.rootUri.empty ? string.init : uriToPath(context.rootUri);
	if (root.empty)
		return files;
	if (isFile(root))
	{
		addFile(root);
		return files;
	}
	try foreach (entry; dirEntries(root, SpanMode.depth))
	{
		if (!isFile(entry.name))
			continue;
		immutable ext = extension(entry.name);
		if (ext != ".d" && ext != ".di")
			continue;
		addFile(entry.name);
	}
	catch (Exception e)
	{
		warningf("Workspace scan failed for %s: %s", root, e.msg);
	}
	return files;
}

/**
 * Computes the module name a file at the given path would have: its path
 * relative to the most specific (deepest) import path containing it, in
 * dotted form. `package.d` files map to their directory's name. Returns an
 * empty string when the path lies outside every import path, in which case
 * its module name cannot be derived.
 */
private string moduleNameForPath(string path, ref ServerContext context)
{
	import std.path : baseName, dirName, stripExtension;

	string best;
	foreach (importPath; context.cache.getImportPaths())
	{
		string imp = importPath;
		while (imp.endsWith("/"))
			imp = imp[0 .. $ - 1];
		if (!path.startsWith(imp))
			continue;
		string rest = path[imp.length .. $];
		if (rest.empty || rest[0] != '/')
			continue; // the path itself, or a partial segment match
		rest = rest[1 .. $];
		// The most specific import path wins: source/helper.d is module
		// "helper" when both the workspace root and source/ are import
		// paths, not "source.helper".
		if (best.empty || rest.length < best.length)
			best = rest;
	}
	if (best.empty)
		return null;
	best = best.stripExtension;
	if (baseName(best) == "package")
	{
		best = dirName(best);
		if (best == "." || best.empty)
			return null; // a package.d directly in an import path root
	}
	return best.replace("/", ".");
}

/**
 * Whether a module name use refers to the renamed module: an exact match,
 * or — when a folder was renamed, moving every file inside it — a
 * submodule of the renamed package. A file rename only changes that one
 * module.
 */
private bool moduleNameMatches(string[] segments, string[] oldSegments, bool folder)
{
	if (segments.length < oldSegments.length)
		return false;
	foreach (i, segment; oldSegments)
		if (segments[i] != segment)
			return false;
	return folder || segments.length == oldSegments.length;
}

/**
 * Handles `workspace/willRenameFiles`.
 *
 * The client sends this request before files or folders are renamed from
 * within the editor (explorer rename/move, or applying a workspace edit).
 * For every renamed path whose module name changes, the handler returns
 * text edits that
 *
 * - rewrite the `module` declaration of the renamed file(s) to the new
 *   module name, and
 * - rewrite every import of the old module name (including submodules,
 *   when a folder was renamed) across the workspace's D files.
 *
 * The edits are anchored to the OLD URIs because the client applies them
 * BEFORE performing the rename (LSP file operations). Library sources on
 * the import paths are never edited: they are read-only.
 *
 * Like serve-d's module renaming, only module declarations and import
 * chains are rewritten; qualified usages of the module name in expressions
 * (e.g. `helper.cheer()` after `import helper;` became `import greeter;`)
 * are left to the user — telling them apart from same-named variables
 * requires full semantic resolution.
 */
JSONValue handleWillRenameFiles(ref ServerContext context, JSONValue params)
{
	import std.file : isDir;
	import dparse.lexer : LexerConfig, StringCache, getTokensForParser;

	// (old module, new module, folder rename?) for each renamed path
	static struct ModuleRename
	{
		string[] oldSegments;
		string[] newSegments;
		bool folder;
	}

	if (params.type != JSONType.object
		|| "files" !in params || params["files"].type != JSONType.array)
		return JSONValue(null);

	ModuleRename[] renames;
	foreach (file; params["files"].array)
	{
		if (file.type != JSONType.object
			|| "oldUri" !in file || file["oldUri"].type != JSONType.string
			|| "newUri" !in file || file["newUri"].type != JSONType.string)
			continue;
		string oldPath = uriToPath(file["oldUri"].str);
		string newPath = uriToPath(file["newUri"].str);
		string oldModule = moduleNameForPath(oldPath, context);
		string newModule = moduleNameForPath(newPath, context);
		if (oldModule.empty || newModule.empty || oldModule == newModule)
			continue;
		ModuleRename rename;
		rename.oldSegments = oldModule.split('.');
		rename.newSegments = newModule.split('.');
		// The rename has not happened yet, so the old path still exists and
		// its type tells file renames (exact module match) apart from
		// folder renames (submodules move too).
		rename.folder = isDir(oldPath);
		renames ~= rename;
	}
	if (renames.empty)
		return JSONValue(null);

	// Scan the workspace's D files: the renamed files themselves plus
	// every potential importer.
	string[] files = collectWorkspaceDFiles(context);
	if (files.empty)
		return JSONValue(null);

	// Cheap pre-filter: a file can only contain a matching chain if it
	// contains the first segment of one of the old module names.
	string[] needles;
	foreach (rename; renames)
		if (!needles.canFind(rename.oldSegments[0]))
			needles ~= rename.oldSegments[0];

	JSONValue[] documentChanges;
	foreach (file; files)
	{
		string uri = pathToUri(file);
		// Prefer the in-memory text of open documents: the client applies
		// the edits to the open buffer, so offsets must match it.
		TextDocument* doc = context.documents.get(uri);
		if (doc is null)
			doc = documentForFile(context, file);
		if (doc is null)
			continue;
		if (!needles.any!(n => doc.text.canFind(n)))
			continue;

		LexerConfig config;
		config.fileName = file;
		// clampedBucketCount guards against the empty-document crash
		auto stringCache = StringCache(clampedBucketCount(doc.text.length));
		auto tokens = getTokensForParser(cast(ubyte[]) doc.text, config, &stringCache);

		JSONValue[] edits;
		foreach (use; scanModuleNameUses(tokens))
		{
			foreach (ref rename; renames)
			{
				if (!moduleNameMatches(use.segments, rename.oldSegments,
						rename.folder))
					continue;
				// The new name: the new module plus the use's segments
				// below the renamed package (empty for exact matches).
				string newText = rename.newSegments.join(".");
				if (use.segments.length > rename.oldSegments.length)
					newText ~= "." ~ use.segments[rename.oldSegments.length .. $]
						.join(".");
				TextEdit edit;
				edit.range = Range(
					context.converter.toPosition(*doc, use.start),
					context.converter.toPosition(*doc, use.end));
				edit.newText = newText;
				edits ~= edit.toJson();
				break; // a use matches at most one rename
			}
		}
		if (!edits.empty)
			documentChanges ~= textDocumentEdit(uri, edits);
	}

	if (documentChanges.empty)
		return JSONValue(null);
	JSONValue result = parseJSON(`{}`);
	result["documentChanges"] = JSONValue(documentChanges);
	return result;
}
