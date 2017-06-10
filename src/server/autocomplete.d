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
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module server.autocomplete;

import std.algorithm;
import std.experimental.allocator;
import std.experimental.logger;
import std.array;
import std.conv;
import std.experimental.logger;
import std.file;
import std.path;
import std.range;
import std.stdio;
import std.string;
import std.typecons;
import std.uni;

import dparse.ast;
import dparse.lexer;
import dparse.parser;
import dparse.rollback_allocator;

import dsymbol.conversion;
import dsymbol.modulecache;
import dsymbol.string_interning;
import dsymbol.symbol;
import dsymbol.scope_;
import dsymbol.builtin.names;
import dsymbol.builtin.symbols;

import common.constants;
import common.messages;

import containers.hashset;

/**
 * Gets documentation for the symbol at the cursor
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
public AutocompleteResponse getDoc(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
//	trace("Getting doc comments");
	AutocompleteResponse response;
	RollbackAllocator rba;
	auto allocator = scoped!(ASTAllocator)();
	auto cache = StringCache(StringCache.defaultBucketCount);
	SymbolStuff stuff = getSymbolsForCompletion(request, CompletionType.ddoc,
		allocator, &rba, cache, moduleCache);
	if (stuff.symbols.length == 0)
		warning("Could not find symbol");
	else
	{
		Appender!(char[]) app;

		bool isDitto(string s)
		{
			import std.uni : icmp;
			if (s.length > 5)
				return false;
			else
				return s.icmp("ditto") == 0;
		}

		void putDDocChar(char c)
		{
			switch (c)
			{
			case '\\':
				app.put('\\');
				app.put('\\');
				break;
			case '\n':
				app.put('\\');
				app.put('n');
				break;
			default:
				app.put(c);
				break;
			}
		}

		void putDDocString(string s)
		{
			foreach (char c; s)
				putDDocChar(c);
		}

		foreach(ref symbol; stuff.symbols.filter!(a => !a.doc.empty && !isDitto(a.doc)))
		{
			app.clear;
			putDDocString(symbol.doc);
			response.docComments ~= app.data.idup;
		}
	}
	return response;
}

/**
 * Finds the declaration of the symbol at the cursor position.
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
public AutocompleteResponse findDeclaration(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
	AutocompleteResponse response;
	RollbackAllocator rba;
	auto allocator = scoped!(ASTAllocator)();
	auto cache = StringCache(StringCache.defaultBucketCount);
	SymbolStuff stuff = getSymbolsForCompletion(request,
		CompletionType.location, allocator, &rba, cache, moduleCache);
	scope(exit) stuff.destroy();
	if (stuff.symbols.length > 0)
	{
		response.symbolLocation = stuff.symbols[0].location;
		response.symbolFilePath = stuff.symbols[0].symbolFile.idup;
	}
	else
		warning("Could not find symbol declaration");
	return response;
}

/**
 * Handles autocompletion
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
public AutocompleteResponse complete(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
	const(Token)[] tokenArray;
	auto stringCache = StringCache(StringCache.defaultBucketCount);
	auto beforeTokens = getTokensBeforeCursor(request.sourceCode,
		request.cursorPosition, stringCache, tokenArray);
	if (beforeTokens.length >= 2)
	{
		if (beforeTokens[$ - 1] == tok!"(" || beforeTokens[$ - 1] == tok!"[")
		{
			return parenCompletion(beforeTokens, tokenArray, request.cursorPosition,
				moduleCache);
		}
		else if (beforeTokens[$ - 1] == tok!",")
		{
			immutable size_t end = goBackToOpenParen(beforeTokens);
			if (end != size_t.max)
				return parenCompletion(beforeTokens[0 .. end], tokenArray,
					request.cursorPosition, moduleCache);
		}
		else
		{
			ImportKind kind = determineImportKind(beforeTokens);
			if (kind == ImportKind.neither)
			{
				if (beforeTokens.isUdaExpression)
					beforeTokens = beforeTokens[$-1 .. $];
				return dotCompletion(beforeTokens, tokenArray, request.cursorPosition,
					moduleCache);
            }
			else
				return importCompletion(beforeTokens, kind, moduleCache);
		}
	}
	return dotCompletion(beforeTokens, tokenArray, request.cursorPosition, moduleCache);
}

/**
 *
 */
public AutocompleteResponse symbolSearch(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
	import containers.ttree : TTree;

	LexerConfig config;
	config.fileName = "";
	auto cache = StringCache(StringCache.defaultBucketCount);
	const(Token)[] tokenArray = getTokensForParser(cast(ubyte[]) request.sourceCode,
		config, &cache);
	auto allocator = scoped!(ASTAllocator)();
	RollbackAllocator rba;
	ScopeSymbolPair pair = generateAutocompleteTrees(tokenArray, allocator,
		&rba, request.cursorPosition, moduleCache);
	scope(exit) pair.destroy();

	static struct SearchResults
	{
		void put(const(DSymbol)* symbol)
		{
			tree.insert(SearchResult(symbol));
		}

		static struct SearchResult
		{
			const(DSymbol)* symbol;

			int opCmp(ref const SearchResult other) const pure nothrow
			{
				if (other.symbol.symbolFile < symbol.symbolFile)
					return -1;
				if (other.symbol.symbolFile > symbol.symbolFile)
					return 1;
				if (other.symbol.location < symbol.location)
					return -1;
				return other.symbol.location > symbol.location;
			}
		}

		TTree!(SearchResult) tree;
	}

	SearchResults results;
	HashSet!size_t visited;
	foreach (symbol; pair.scope_.symbols)
		symbol.getParts!SearchResults(internString(request.searchName), results, visited);
	foreach (s; moduleCache.getAllSymbols())
		s.symbol.getParts!SearchResults(internString(request.searchName), results, visited);

	AutocompleteResponse response;
	foreach (result; results.tree[])
	{
		response.locations ~= result.symbol.location;
		response.completionKinds ~= result.symbol.kind;
		response.completions ~= result.symbol.symbolFile;
	}

	return response;
}

/******************************************************************************/
private:

enum ImportKind : ubyte
{
	selective,
	normal,
	neither
}

/**
 * Handles dot completion for identifiers and types.
 * Params:
 *     beforeTokens = the tokens before the cursor
 *     tokenArray = all tokens in the file
 *     cursorPosition = the cursor position in bytes
 * Returns:
 *     the autocompletion response
 */
AutocompleteResponse dotCompletion(T)(T beforeTokens, const(Token)[] tokenArray,
	size_t cursorPosition, ref ModuleCache moduleCache)
{
	AutocompleteResponse response;

	// Partial symbol name appearing after the dot character and before the
	// cursor.
	string partial;

	// Type of the token before the dot, or identifier if the cursor was at
	// an identifier.
	IdType significantTokenType;

	if (beforeTokens.length >= 1 && beforeTokens[$ - 1] == tok!"identifier")
	{
		// Set partial to the slice of the identifier between the beginning
		// of the identifier and the cursor. This improves the completion
		// responses when the cursor is in the middle of an identifier instead
		// of at the end
		auto t = beforeTokens[$ - 1];
		if (cursorPosition - t.index >= 0 && cursorPosition - t.index <= t.text.length)
			partial = t.text[0 .. cursorPosition - t.index];
		significantTokenType = tok!"identifier";
		beforeTokens = beforeTokens[0 .. $ - 1];
	}
	else if (beforeTokens.length >= 2 && beforeTokens[$ - 1] ==  tok!".")
		significantTokenType = beforeTokens[$ - 2].type;
	else
		return response;

	switch (significantTokenType)
	{
	case tok!"stringLiteral":
	case tok!"wstringLiteral":
	case tok!"dstringLiteral":
		foreach (symbol; arraySymbols)
		{
			response.completionKinds ~= symbol.kind;
			response.completions ~= symbol.name.dup;
		}
		response.completionType = CompletionType.identifiers;
		break;
	case tok!"int":
	case tok!"uint":
	case tok!"long":
	case tok!"ulong":
	case tok!"char":
	case tok!"wchar":
	case tok!"dchar":
	case tok!"bool":
	case tok!"byte":
	case tok!"ubyte":
	case tok!"short":
	case tok!"ushort":
	case tok!"cent":
	case tok!"ucent":
	case tok!"float":
	case tok!"ifloat":
	case tok!"cfloat":
	case tok!"idouble":
	case tok!"cdouble":
	case tok!"double":
	case tok!"real":
	case tok!"ireal":
	case tok!"creal":
	case tok!"identifier":
	case tok!")":
	case tok!"]":
	case tok!"this":
	case tok!"super":
		auto allocator = scoped!(ASTAllocator)();
		RollbackAllocator rba;
		ScopeSymbolPair pair = generateAutocompleteTrees(tokenArray, allocator,
			&rba, cursorPosition, moduleCache);
		scope(exit) pair.destroy();
		response.setCompletions(pair.scope_, getExpression(beforeTokens),
			cursorPosition, CompletionType.identifiers, false, partial);
		break;
	case tok!"(":
	case tok!"{":
	case tok!"[":
	case tok!";":
	case tok!":":
		break;
	default:
		break;
	}
	return response;
}

/**
 * Params:
 *     sourceCode = the source code of the file being edited
 *     cursorPosition = the cursor position in bytes
 * Returns:
 *     a sorted range of tokens before the cursor position
 */
auto getTokensBeforeCursor(const(ubyte[]) sourceCode, size_t cursorPosition,
	ref StringCache cache, out const(Token)[] tokenArray)
{
	LexerConfig config;
	config.fileName = "";
	tokenArray = getTokensForParser(cast(ubyte[]) sourceCode, config, &cache);
	auto sortedTokens = assumeSorted(tokenArray);
	return sortedTokens.lowerBound(cast(size_t) cursorPosition);
}

/**
 * Params:
 *     request = the autocompletion request
 *     type = type the autocompletion type
 * Returns:
 *     all symbols that should be considered for the autocomplete list based on
 *     the request's source code, cursor position, and completion type.
 */
SymbolStuff getSymbolsForCompletion(const AutocompleteRequest request,
	const CompletionType type, IAllocator allocator, RollbackAllocator* rba,
	ref StringCache cache, ref ModuleCache moduleCache)
{
	const(Token)[] tokenArray;
	auto beforeTokens = getTokensBeforeCursor(request.sourceCode,
		request.cursorPosition, cache, tokenArray);
	ScopeSymbolPair pair = generateAutocompleteTrees(tokenArray, allocator,
		rba, request.cursorPosition, moduleCache);
	auto expression = getExpression(beforeTokens);
	return SymbolStuff(getSymbolsByTokenChain(pair.scope_, expression,
		request.cursorPosition, type), pair.symbol, pair.scope_);
}

struct SymbolStuff
{
	void destroy()
	{
		typeid(DSymbol).destroy(symbol);
		typeid(Scope).destroy(scope_);
	}

	DSymbol*[] symbols;
	DSymbol* symbol;
	Scope* scope_;
}

/**
 * Handles paren completion for function calls and some keywords
 * Params:
 *     beforeTokens = the tokens before the cursor
 *     tokenArray = all tokens in the file
 *     cursorPosition = the cursor position in bytes
 * Returns:
 *     the autocompletion response
 */
AutocompleteResponse parenCompletion(T)(T beforeTokens,
	const(Token)[] tokenArray, size_t cursorPosition, ref ModuleCache moduleCache)
{
	AutocompleteResponse response;
	immutable(string)[] completions;
	switch (beforeTokens[$ - 2].type)
	{
	case tok!"__traits":
		completions = traits;
		goto fillResponse;
	case tok!"scope":
		completions = scopes;
		goto fillResponse;
	case tok!"version":
		completions = predefinedVersions;
		goto fillResponse;
	case tok!"extern":
		completions = linkages;
		goto fillResponse;
	case tok!"pragma":
		completions = pragmas;
	fillResponse:
		response.completionType = CompletionType.identifiers;
		foreach (completion; completions)
		{
			response.completions ~= completion;
			response.completionKinds ~= CompletionKind.keyword;
		}
		break;
	case tok!"characterLiteral":
	case tok!"doubleLiteral":
	case tok!"dstringLiteral":
	case tok!"floatLiteral":
	case tok!"identifier":
	case tok!"idoubleLiteral":
	case tok!"ifloatLiteral":
	case tok!"intLiteral":
	case tok!"irealLiteral":
	case tok!"longLiteral":
	case tok!"realLiteral":
	case tok!"stringLiteral":
	case tok!"uintLiteral":
	case tok!"ulongLiteral":
	case tok!"wstringLiteral":
	case tok!"this":
	case tok!"super":
	case tok!")":
	case tok!"]":
		auto allocator = scoped!(ASTAllocator)();
		RollbackAllocator rba;
		ScopeSymbolPair pair = generateAutocompleteTrees(tokenArray, allocator,
			&rba, cursorPosition, moduleCache);
		scope(exit) pair.destroy();
		auto expression = getExpression(beforeTokens[0 .. $ - 1]);
		response.setCompletions(pair.scope_, expression,
			cursorPosition, CompletionType.calltips, beforeTokens[$ - 1] == tok!"[");
		break;
	default:
		break;
	}
	return response;
}

/**
 * Determines if an import is selective, whole-module, or neither.
 */
ImportKind determineImportKind(T)(T tokens)
{
	assert (tokens.length > 1);
	size_t i = tokens.length - 1;
	if (!(tokens[i] == tok!":" || tokens[i] == tok!"," || tokens[i] == tok!"."
			|| tokens[i] == tok!"identifier"))
		return ImportKind.neither;
	bool foundColon = false;
	while (true) switch (tokens[i].type)
	{
	case tok!":":
		foundColon = true;
		goto case;
	case tok!"identifier":
	case tok!"=":
	case tok!".":
	case tok!",":
		if (i == 0)
			return ImportKind.neither;
		else
			i--;
		break;
	case tok!"import":
		return foundColon ? ImportKind.selective : ImportKind.normal;
	default:
		return ImportKind.neither;
	}
	return ImportKind.neither;
}

unittest
{
	import std.stdio : writeln;

	Token[] t = [
		Token(tok!"import"), Token(tok!"identifier"), Token(tok!"."),
		Token(tok!"identifier"), Token(tok!":"), Token(tok!"identifier"), Token(tok!",")
	];
	assert(determineImportKind(t) == ImportKind.selective);
	Token[] t2;
	t2 ~= Token(tok!"else");
	t2 ~= Token(tok!":");
	assert(determineImportKind(t2) == ImportKind.neither);
	writeln("Unittest for determineImportKind() passed");
}

/**
 * Provides autocomplete for selective imports, e.g.:
 * ---
 * import std.algorithm: balancedParens;
 * ---
 */
AutocompleteResponse importCompletion(T)(T beforeTokens, ImportKind kind,
	ref ModuleCache moduleCache)
in
{
	assert (beforeTokens.length >= 2);
}
body
{
	AutocompleteResponse response;
	if (beforeTokens.length <= 2)
		return response;

	size_t i = beforeTokens.length - 1;

	if (kind == ImportKind.normal)
	{

		while (beforeTokens[i].type != tok!"," && beforeTokens[i].type != tok!"import"
				&& beforeTokens[i].type != tok!"=" )
			i--;
		setImportCompletions(beforeTokens[i .. $], response, moduleCache);
		return response;
	}

	loop: while (true) switch (beforeTokens[i].type)
	{
	case tok!"identifier":
	case tok!"=":
	case tok!",":
	case tok!".":
		i--;
		break;
	case tok!":":
		i--;
		while (beforeTokens[i].type == tok!"identifier" || beforeTokens[i].type == tok!".")
			i--;
		break loop;
	default:
		break loop;
	}

	size_t j = i;
	loop2: while (j <= beforeTokens.length) switch (beforeTokens[j].type)
	{
	case tok!":": break loop2;
	default: j++; break;
	}

	if (i >= j)
	{
		warning("Malformed import statement");
		return response;
	}

	immutable string path = beforeTokens[i + 1 .. j]
		.filter!(token => token.type == tok!"identifier")
		.map!(token => cast() token.text)
		.joiner(dirSeparator)
		.text();

	string resolvedLocation = moduleCache.resolveImportLocation(path);
	if (resolvedLocation is null)
	{
		warning("Could not resolve location of ", path);
		return response;
	}
	auto symbols = moduleCache.getModuleSymbol(internString(resolvedLocation));

	import containers.hashset : HashSet;
	HashSet!string h;

	void addSymbolToResponses(const(DSymbol)* sy)
	{
		auto a = DSymbol(sy.name);
		if (!builtinSymbols.contains(&a) && sy.name !is null && !h.contains(sy.name)
				&& !sy.skipOver && sy.name != CONSTRUCTOR_SYMBOL_NAME
				&& isPublicCompletionKind(sy.kind))
		{
			response.completionKinds ~= sy.kind;
			response.completions ~= sy.name;
			h.insert(sy.name);
		}
	}

	foreach (s; symbols.opSlice().filter!(a => !a.skipOver))
	{
		if (s.kind == CompletionKind.importSymbol && s.type !is null)
			foreach (sy; s.type.opSlice().filter!(a => !a.skipOver))
				addSymbolToResponses(sy);
		else
			addSymbolToResponses(s);
	}
	response.completionType = CompletionType.identifiers;
	return response;
}

/**
 * Populates the response with completion information for an import statement
 * Params:
 *     tokens = the tokens after the "import" keyword and before the cursor
 *     response = the response that should be populated
 */
void setImportCompletions(T)(T tokens, ref AutocompleteResponse response,
	ref ModuleCache cache)
{
	response.completionType = CompletionType.identifiers;
	string partial = null;
	if (tokens[$ - 1].type == tok!"identifier")
	{
		partial = tokens[$ - 1].text;
		tokens = tokens[0 .. $ - 1];
	}
	auto moduleParts = tokens.filter!(a => a.type == tok!"identifier").map!("a.text").array();
	string path = buildPath(moduleParts);

	bool found = false;

	foreach (importPath; cache.getImportPaths())
	{
		if (importPath.isFile)
		{
			if (!exists(importPath))
				continue;

			found = true;

			auto n = importPath.baseName(".d").baseName(".di");
			if (isFile(importPath) && (importPath.endsWith(".d") || importPath.endsWith(".di"))
					&& (partial is null || n.startsWith(partial)))
			{
				response.completions ~= n;
				response.completionKinds ~= CompletionKind.moduleName;
			}
		}
		else
		{
			string p = buildPath(importPath, path);
			if (!exists(p))
				continue;

			found = true;

			try foreach (string name; dirEntries(p, SpanMode.shallow))
			{
				import std.path: baseName;
				if (name.baseName.startsWith(".#"))
					continue;

				auto n = name.baseName(".d").baseName(".di");
				if (isFile(name) && (name.endsWith(".d") || name.endsWith(".di"))
					&& (partial is null || n.startsWith(partial)))
				{
					response.completions ~= n;
					response.completionKinds ~= CompletionKind.moduleName;
				}
				else if (isDir(name))
				{
					if (n[0] != '.' && (partial is null || n.startsWith(partial)))
					{
						response.completions ~= n;
						response.completionKinds ~=
							exists(buildPath(name, "package.d")) || exists(buildPath(name, "package.di"))
							? CompletionKind.moduleName : CompletionKind.packageName;
					}
				}
			}
			catch(FileException){}
		}
	}
	if (!found)
		warning("Could not find ", moduleParts);
}

static void skip(alias O, alias C, T)(T t, ref size_t i)
{
	int depth = 1;
	while (i < t.length) switch (t[i].type)
	{
	case O:
		i++;
		depth++;
		break;
	case C:
		i++;
		depth--;
		if (depth <= 0)
			return;
		break;
	default:
		i++;
		break;
	}
}

bool isSliceExpression(T)(T tokens, size_t index)
{
	while (index < tokens.length) switch (tokens[index].type)
	{
	case tok!"[":
		skip!(tok!"[", tok!"]")(tokens, index);
		break;
	case tok!"(":
		skip!(tok!"(", tok!")")(tokens, index);
		break;
	case tok!"]":
	case tok!"}":
		return false;
	case tok!"..":
		return true;
	default:
		index++;
		break;
	}
	return false;
}

/**
 *
 */
DSymbol*[] getSymbolsByTokenChain(T)(Scope* completionScope,
	T tokens, size_t cursorPosition, CompletionType completionType)
{
	//writeln(">>>");
	//dumpTokens(tokens.release);
	//writeln(">>>");

	static size_t skipEnd(T tokenSlice, size_t i, IdType open, IdType close)
	{
		size_t j = i + 1;
		for (int depth = 1; depth > 0 && j < tokenSlice.length; j++)
		{
			if (tokenSlice[j].type == open)
				depth++;
			else if (tokenSlice[j].type == close)
			{
				depth--;
				if (depth == 0) break;
			}
		}
		return j;
	}

	// Find the symbol corresponding to the beginning of the chain
	DSymbol*[] symbols;
	if (tokens.length == 0)
		return [];
	// Recurse in case the symbol chain starts with an expression in parens
	// e.g. (a.b!c).d
	if (tokens[0] == tok!"(")
	{
		immutable j = skipEnd(tokens, 0, tok!"(", tok!")");
		symbols = getSymbolsByTokenChain(completionScope, tokens[1 .. j],
				cursorPosition, completionType);
		tokens = tokens[j + 1 .. $];
		//writeln("<<<");
		//dumpTokens(tokens.release);
		//writeln("<<<");
		if (tokens.length == 0) // workaround (#371)
			return [];
	}
	else if (tokens[0] == tok!"." && tokens.length > 1)
	{
		tokens = tokens[1 .. $];
		if (tokens.length == 0)	// workaround (#371)
			return [];
		symbols = completionScope.getSymbolsAtGlobalScope(stringToken(tokens[0]));
	}
	else
		symbols = completionScope.getSymbolsByNameAndCursor(stringToken(tokens[0]), cursorPosition);

	if (symbols.length == 0)
	{
		//TODO: better bugfix for issue #368, see test case 52 or pull #371
		if (tokens.length)
			warning("Could not find declaration of ", stringToken(tokens[0]),
				" from position ", cursorPosition);
		else assert(0, "internal error");
		return [];
	}

	// If the `symbols` array contains functions, and one of them returns
	// void and the others do not, this is a property function. For the
	// purposes of chaining auto-complete we want to ignore the one that
	// returns void. This is a no-op if we are getting doc comments.
	void filterProperties() @nogc @safe
	{
		if (symbols.length == 0 || completionType == CompletionType.ddoc)
			return;
		if (symbols[0].kind == CompletionKind.functionName
			|| symbols[0].qualifier == SymbolQualifier.func)
		{
			int voidRets = 0;
			int nonVoidRets = 0;
			size_t firstNonVoidIndex = size_t.max;
			foreach (i, sym; symbols)
			{
				if (sym.type is null)
					return;
				if (&sym.type.name[0] == &getBuiltinTypeName(tok!"void")[0])
					voidRets++;
				else
				{
					nonVoidRets++;
					firstNonVoidIndex = min(firstNonVoidIndex, i);
				}
			}
			if (voidRets > 0 && nonVoidRets > 0)
				symbols = symbols[firstNonVoidIndex .. $];
		}
	}

	filterProperties();

	if (shouldSwapWithType(completionType, symbols[0].kind, 0, tokens.length - 1))
	{
		//trace("Swapping types");
		if (symbols.length == 0 || symbols[0].type is null || symbols[0].type is symbols[0])
			return [];
		else if (symbols[0].type.kind == CompletionKind.functionName)
		{
			if (symbols[0].type.type is null)
				symbols = [];
			else
				symbols = [symbols[0].type.type];
		}
		else
			symbols = [symbols[0].type];
	}

	loop: for (size_t i = 1; i < tokens.length; i++)
	{
		void skip(IdType open, IdType close)
		{
			i = skipEnd(tokens, i, open, close);
		}

		switch (tokens[i].type)
		{
		case tok!"int":
		case tok!"uint":
		case tok!"long":
		case tok!"ulong":
		case tok!"char":
		case tok!"wchar":
		case tok!"dchar":
		case tok!"bool":
		case tok!"byte":
		case tok!"ubyte":
		case tok!"short":
		case tok!"ushort":
		case tok!"cent":
		case tok!"ucent":
		case tok!"float":
		case tok!"ifloat":
		case tok!"cfloat":
		case tok!"idouble":
		case tok!"cdouble":
		case tok!"double":
		case tok!"real":
		case tok!"ireal":
		case tok!"creal":
		case tok!"this":
		case tok!"super":
			symbols = symbols[0].getPartsByName(internString(str(tokens[i].type)));
			if (symbols.length == 0)
				break loop;
			break;
		case tok!"identifier":
			//trace(symbols[0].qualifier, " ", symbols[0].kind);
			filterProperties();

			if (symbols.length == 0)
				break loop;

			// Use type instead of the symbol itself for certain symbol kinds
			while (symbols[0].qualifier == SymbolQualifier.func
				|| symbols[0].kind == CompletionKind.functionName
				|| (symbols[0].kind == CompletionKind.moduleName
					&& symbols[0].type !is null && symbols[0].type.kind == CompletionKind.importSymbol)
				|| symbols[0].kind == CompletionKind.importSymbol
				|| symbols[0].kind == CompletionKind.aliasName)
			{
				symbols = symbols[0].type is null || symbols[0].type is symbols[0] ? [] : [symbols[0].type];
				if (symbols.length == 0)
					break loop;
			}

			//trace("looking for ", tokens[i].text, " in ", symbols[0].name);
			symbols = symbols[0].getPartsByName(internString(tokens[i].text));
			//trace("symbols: ", symbols.map!(a => a.name));
			filterProperties();
			if (symbols.length == 0)
			{
				//trace("Couldn't find it.");
				break loop;
			}
			if (shouldSwapWithType(completionType, symbols[0].kind, i, tokens.length - 1))
			{
				symbols = symbols[0].type is null || symbols[0].type is symbols[0] ? [] : [symbols[0].type];
				if (symbols.length == 0)
					break loop;
			}
			if ((symbols[0].kind == CompletionKind.aliasName
				|| symbols[0].kind == CompletionKind.moduleName)
				&& (completionType == CompletionType.identifiers
				|| i + 1 < tokens.length))
			{
				symbols = symbols[0].type is null || symbols[0].type is symbols[0] ? [] : [symbols[0].type];
			}
			if (symbols.length == 0)
				break loop;
			if (tokens[i].type == tok!"!")
			{
				i++;
				if (tokens[i].type == tok!"(")
					goto case;
				else
					i++;
			}
			break;
		case tok!"(":
			skip(tok!"(", tok!")");
			break;
		case tok!"[":
			if (symbols[0].qualifier == SymbolQualifier.array)
			{
				skip(tok!"[", tok!"]");
				if (!isSliceExpression(tokens, i))
				{
					symbols = symbols[0].type is null || symbols[0].type is symbols[0] ? [] : [symbols[0].type];
					if (symbols.length == 0)
						break loop;
				}
			}
			else if (symbols[0].qualifier == SymbolQualifier.assocArray)
			{
				symbols = symbols[0].type is null || symbols[0].type is symbols[0] ? [] : [symbols[0].type];
				skip(tok!"[", tok!"]");
			}
			else
			{
				skip(tok!"[", tok!"]");
				DSymbol*[] overloads;
				if (isSliceExpression(tokens, i))
					overloads = symbols[0].getPartsByName(internString("opSlice"));
				else
					overloads = symbols[0].getPartsByName(internString("opIndex"));
				if (overloads.length > 0)
				{
					symbols = overloads[0].type is null ? [] : [overloads[0].type];
				}
				else
					return [];
			}
			break;
		case tok!".":
			break;
		default:
			break loop;
		}
	}
	return symbols;
}

/**
 *
 */
void setCompletions(T)(ref AutocompleteResponse response,
	Scope* completionScope, T tokens, size_t cursorPosition,
	CompletionType completionType, bool isBracket = false, string partial = null)
{
	static void addSymToResponse(const(DSymbol)* s, ref AutocompleteResponse r, string p,
		size_t[] circularGuard = [])
	{
		if (circularGuard.canFind(cast(size_t) s))
			return;
		foreach (sym; s.opSlice())
		{
			if (sym.name !is null && sym.name.length > 0 && isPublicCompletionKind(sym.kind)
				&& (p is null ? true : toUpper(sym.name.data).startsWith(toUpper(p)))
				&& !r.completions.canFind(sym.name)
				&& sym.name[0] != '*')
			{
				r.completionKinds ~= sym.kind;
				r.completions ~= sym.name.dup;
			}
			if (sym.kind == CompletionKind.importSymbol && !sym.skipOver && sym.type !is null)
				addSymToResponse(sym.type, r, p, circularGuard ~ (cast(size_t) s));
		}
	}

	// Handle the simple case where we get all symbols in scope and filter it
	// based on the currently entered text.
	if (partial !is null && tokens.length == 0)
	{
		auto currentSymbols = completionScope.getSymbolsInCursorScope(cursorPosition);
		foreach (s; currentSymbols.filter!(a => isPublicCompletionKind(a.kind)
				&& toUpper(a.name.data).startsWith(toUpper(partial))))
		{
			response.completionKinds ~= s.kind;
			response.completions ~= s.name.dup;
		}
		response.completionType = CompletionType.identifiers;
		return;
	}

	if (tokens.length == 0)
		return;

	DSymbol*[] symbols = getSymbolsByTokenChain(completionScope, tokens,
		cursorPosition, completionType);

	if (symbols.length == 0)
		return;

	if (completionType == CompletionType.identifiers)
	{
		while (symbols[0].qualifier == SymbolQualifier.func
				|| symbols[0].kind == CompletionKind.functionName
				|| symbols[0].kind == CompletionKind.importSymbol
				|| symbols[0].kind == CompletionKind.aliasName)
		{
			symbols = symbols[0].type is null || symbols[0].type is symbols[0] ? []
				: [symbols[0].type];
			if (symbols.length == 0)
				return;
		}
		addSymToResponse(symbols[0], response, partial);
		response.completionType = CompletionType.identifiers;
	}
	else if (completionType == CompletionType.calltips)
	{
		//trace("Showing call tips for ", symbols[0].name, " of kind ", symbols[0].kind);
		if (symbols[0].kind != CompletionKind.functionName
			&& symbols[0].callTip is null)
		{
			if (symbols[0].kind == CompletionKind.aliasName)
			{
				if (symbols[0].type is null || symbols[0].type is symbols[0])
					return;
				symbols = [symbols[0].type];
			}
			if (symbols[0].kind == CompletionKind.variableName)
			{
				auto dumb = symbols[0].type;
				if (dumb !is null)
				{
					if (dumb.kind == CompletionKind.functionName)
					{
						symbols = [dumb];
						goto setCallTips;
					}
					if (isBracket)
					{
						auto index = dumb.getPartsByName(internString("opIndex"));
						if (index.length > 0)
						{
							symbols = index;
							goto setCallTips;
						}
					}
					auto call = dumb.getPartsByName(internString("opCall"));
					if (call.length > 0)
					{
						symbols = call;
						goto setCallTips;
					}
				}
			}
			if (symbols[0].kind == CompletionKind.structName
				|| symbols[0].kind == CompletionKind.className)
			{
				auto constructor = symbols[0].getPartsByName(CONSTRUCTOR_SYMBOL_NAME);
				if (constructor.length == 0)
				{
					// Build a call tip out of the struct fields
					if (symbols[0].kind == CompletionKind.structName)
					{
						response.completionType = CompletionType.calltips;
						response.completions = [generateStructConstructorCalltip(symbols[0])];
						return;
					}
				}
				else
				{
					symbols = constructor;
					goto setCallTips;
				}
			}
		}
	setCallTips:
		response.completionType = CompletionType.calltips;
		foreach (symbol; symbols)
		{
			if (symbol.kind != CompletionKind.aliasName && symbol.callTip !is null)
				response.completions ~= symbol.callTip;
		}
	}
}

string generateStructConstructorCalltip(const DSymbol* symbol)
in
{
	assert(symbol.kind == CompletionKind.structName);
}
body
{
	string generatedStructConstructorCalltip = "this(";
	const(DSymbol)*[] fields = symbol.opSlice().filter!(
		a => a.kind == CompletionKind.variableName).map!(a => cast(const(DSymbol)*) a).array();
	fields.sort!((a, b) => a.location < b.location);
	foreach (i, field; fields)
	{
		if (field.kind != CompletionKind.variableName)
			continue;
		i++;
		if (field.type !is null)
		{
			generatedStructConstructorCalltip ~= field.type.name;
			generatedStructConstructorCalltip ~= " ";
		}
		generatedStructConstructorCalltip ~= field.name;
		if (i < fields.length)
			generatedStructConstructorCalltip ~= ", ";
	}
	generatedStructConstructorCalltip ~= ")";
	return generatedStructConstructorCalltip;
}

private enum TYPE_IDENT_AND_LITERAL_CASES = q{
	case tok!"int":
	case tok!"uint":
	case tok!"long":
	case tok!"ulong":
	case tok!"char":
	case tok!"wchar":
	case tok!"dchar":
	case tok!"bool":
	case tok!"byte":
	case tok!"ubyte":
	case tok!"short":
	case tok!"ushort":
	case tok!"cent":
	case tok!"ucent":
	case tok!"float":
	case tok!"ifloat":
	case tok!"cfloat":
	case tok!"idouble":
	case tok!"cdouble":
	case tok!"double":
	case tok!"real":
	case tok!"ireal":
	case tok!"creal":
	case tok!"this":
	case tok!"super":
	case tok!"identifier":
	case tok!"stringLiteral":
	case tok!"wstringLiteral":
	case tok!"dstringLiteral":
};

bool isUdaExpression(T)(ref T tokens)
{
	bool result;
	ptrdiff_t skip;
	ptrdiff_t i = tokens.length - 2;
	
	if (i < 1)
		return result;
	
	// skips the UDA ctor
	if (tokens[i].type == tok!")")
	{
		++skip;
		--i;
		while (i >= 2)
		{
			skip += tokens[i].type == tok!")";
			skip -= tokens[i].type == tok!"(";
			--i;
			if (skip == 0)
			{
				// @UDA!(TemplateParameters)(FunctionParameters)
				if (i > 3 && tokens[i].type == tok!"!" && tokens[i-1].type == tok!")")
				{
					skip = 1;
					i -= 2;
					continue;
				}
				else break;
			}
		}
	}
	
	if (skip == 0)
	{
		// @UDA!SingleTemplateParameter
		if (i > 2 && tokens[i].type == tok!"identifier" && tokens[i-1].type == tok!"!")
		{
			i -= 2;
		}

		// @UDA
		if (i > 0 && tokens[i].type == tok!"identifier" && tokens[i-1].type == tok!"@")
		{
			result = true;
		}
	}
    
	return result;
}

/**
 *
 */
T getExpression(T)(T beforeTokens)
{
	enum EXPRESSION_LOOP_BREAK = q{
		if (i + 1 < beforeTokens.length) switch (beforeTokens[i + 1].type)
		{
		mixin (TYPE_IDENT_AND_LITERAL_CASES);
			i++;
			break expressionLoop;
		default:
			break;
		}
	};

	if (beforeTokens.length == 0)
		return beforeTokens[0 .. 0];
	size_t i = beforeTokens.length - 1;
	size_t sliceEnd = beforeTokens.length;
	IdType open;
	IdType close;
	uint skipCount = 0;

	expressionLoop: while (true)
	{
		switch (beforeTokens[i].type)
		{
		case tok!"import":
			i++;
			break expressionLoop;
		mixin (TYPE_IDENT_AND_LITERAL_CASES);
			mixin (EXPRESSION_LOOP_BREAK);
			break;
		case tok!".":
			break;
		case tok!")":
			open = tok!")";
			close = tok!"(";
			goto skip;
		case tok!"]":
			open = tok!"]";
			close = tok!"[";
		skip:
			mixin (EXPRESSION_LOOP_BREAK);
			immutable bookmark = i;
			int depth = 1;
			do
			{
				if (depth == 0 || i == 0)
					break;
				else
					i--;
				if (beforeTokens[i].type == open)
					depth++;
				else if (beforeTokens[i].type == close)
					depth--;
			} while (true);

			skipCount++;

			// check the current token after skipping parens to the left.
			// if it's a loop keyword, pretend we never skipped the parens.
			if (i > 0) switch (beforeTokens[i - 1].type)
			{
				case tok!"scope":
				case tok!"if":
				case tok!"while":
				case tok!"for":
				case tok!"foreach":
				case tok!"foreach_reverse":
				case tok!"do":
				case tok!"cast":
				case tok!"catch":
					i = bookmark + 1;
					break expressionLoop;
				case tok!"!":
					if (skipCount == 1)
					{
						sliceEnd = i - 1;
						i -= 2;
					}
					break expressionLoop;
				default:
					break;
			}
			break;
		default:
			i++;
			break expressionLoop;
		}
		if (i == 0)
			break;
		else
			i--;
	}
	return beforeTokens[i .. sliceEnd];
}

size_t goBackToOpenParen(T)(T beforeTokens)
in
{
	assert (beforeTokens.length > 0);
}
body
{
	size_t i = beforeTokens.length - 1;
	IdType open;
	IdType close;
	while (true) switch (beforeTokens[i].type)
	{
	case tok!",":
	case tok!".":
	case tok!"*":
	case tok!"&":
	case tok!"doubleLiteral":
	case tok!"floatLiteral":
	case tok!"idoubleLiteral":
	case tok!"ifloatLiteral":
	case tok!"intLiteral":
	case tok!"longLiteral":
	case tok!"realLiteral":
	case tok!"irealLiteral":
	case tok!"uintLiteral":
	case tok!"ulongLiteral":
	case tok!"characterLiteral":
	mixin(TYPE_IDENT_AND_LITERAL_CASES);
		if (i == 0)
			return size_t.max;
		else
			i--;
		break;
	case tok!"(":
	case tok!"[":
		return i + 1;
	case tok!")":
		open = tok!")";
		close = tok!"(";
		goto skip;
	case tok!"}":
		open = tok!"}";
		close = tok!"{";
		goto skip;
	case tok!"]":
		open = tok!"]";
		close = tok!"[";
	skip:
		if (i == 0)
			return size_t.max;
		else
			i--;
		int depth = 1;
		do
		{
			if (depth == 0 || i == 0)
				break;
			else
				i--;
			if (beforeTokens[i].type == open)
				depth++;
			else if (beforeTokens[i].type == close)
				depth--;
		} while (true);
		break;
	default:
		return size_t.max;
	}
	return size_t.max;
}

/**
 * Params:
 *     completionType = the completion type being requested
 *     kind = the kind of the current item in the completion chain
 *     current = the index of the current item in the symbol chain
 *     max = the number of items in the symbol chain
 * Returns:
 *     true if the symbol should be swapped with its type field
 */
bool shouldSwapWithType(CompletionType completionType, CompletionKind kind,
	size_t current, size_t max) pure nothrow @safe
{
	// packages never have types, so always return false
	if (kind == CompletionKind.packageName
		|| kind == CompletionKind.className
		|| kind == CompletionKind.structName
		|| kind == CompletionKind.interfaceName
		|| kind == CompletionKind.enumName
		|| kind == CompletionKind.unionName
		|| kind == CompletionKind.templateName
		|| kind == CompletionKind.keyword)
	{
		return false;
	}
	// Swap out every part of a chain with its type except the last part
	if (current < max)
		return true;
	// Only swap out types for these kinds
	immutable bool isInteresting =
		kind == CompletionKind.variableName
		|| kind == CompletionKind.memberVariableName
		|| kind == CompletionKind.importSymbol
		|| kind == CompletionKind.aliasName
		|| kind == CompletionKind.enumMember
		|| kind == CompletionKind.functionName;
	return isInteresting && (completionType == CompletionType.identifiers
		|| (completionType == completionType.calltips && kind == CompletionKind.variableName)) ;
}

istring stringToken()(auto ref const Token a)
{
	return internString(a.text is null ? str(a.type) : a.text);
}

//void dumpTokens(const Token[] tokens)
//{
	//foreach (t; tokens)
		//writeln(t.line, ":", t.column, " ", stringToken(t));
//}
