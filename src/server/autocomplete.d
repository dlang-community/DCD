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

import std.d.ast;
import std.d.lexer;
import std.d.parser;

import dsymbol.conversion;
import dsymbol.modulecache;
import dsymbol.string_interning;
import dsymbol.symbol;
import dsymbol.scope_;
import dsymbol.builtin.names;
import dsymbol.builtin.symbols;

import memory.allocators;

import common.constants;
import common.messages;

private alias ASTAllocator = CAllocatorImpl!(AllocatorList!(n => Region!Mallocator(1024 * 64)));

/**
 * Gets documentation for the symbol at the cursor
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
public AutocompleteResponse getDoc(const AutocompleteRequest request)
{
//	trace("Getting doc comments");
	AutocompleteResponse response;
	auto allocator = scoped!(ASTAllocator)();
	auto cache = StringCache(StringCache.defaultBucketCount);
	ScopeSymbolPair pair = getSymbolsForCompletion(request, CompletionType.ddoc,
		allocator, &cache);
	if (pair.symbols.length == 0)
		warning("Could not find symbol");
	else foreach (symbol; pair.symbols.filter!(a => !a.doc.empty))
		response.docComments ~= formatComment(symbol.doc);
	return response;
}

/**
 * Finds the declaration of the symbol at the cursor position.
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
public AutocompleteResponse findDeclaration(const AutocompleteRequest request)
{
	AutocompleteResponse response;
	auto allocator = scoped!(ASTAllocator)();
	auto cache = StringCache(StringCache.defaultBucketCount);
	ScopeSymbolPair pair = getSymbolsForCompletion(request,
		CompletionType.location, allocator, &cache);
	if (pair.symbols.length > 0)
	{
		response.symbolLocation = pair.symbols[0].location;
		response.symbolFilePath = pair.symbols[0].symbolFile.idup;
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
public AutocompleteResponse complete(const AutocompleteRequest request)
{
	const(Token)[] tokenArray;
	auto cache = StringCache(StringCache.defaultBucketCount);
	auto beforeTokens = getTokensBeforeCursor(request.sourceCode,
		request.cursorPosition, &cache, tokenArray);
	if (beforeTokens.length >= 2)
	{
		if (beforeTokens[$ - 1] == tok!"(" || beforeTokens[$ - 1] == tok!"[")
		{
			return parenCompletion(beforeTokens, tokenArray, request.cursorPosition);
		}
		else if (beforeTokens[$ - 1] == tok!",")
		{
			immutable size_t end = goBackToOpenParen(beforeTokens);
			if (end != size_t.max)
				return parenCompletion(beforeTokens[0 .. end], tokenArray, request.cursorPosition);
		}
		else
		{
			ImportKind kind = determineImportKind(beforeTokens);
			if (kind == ImportKind.neither)
				return dotCompletion(beforeTokens, tokenArray, request.cursorPosition);
			else
				return importCompletion(beforeTokens, kind);
		}
	}
	return dotCompletion(beforeTokens, tokenArray, request.cursorPosition);
}

/**
 *
 */
public AutocompleteResponse symbolSearch(const AutocompleteRequest request)
{
	import containers.ttree : TTree;

	LexerConfig config;
	config.fileName = "";
	auto cache = StringCache(StringCache.defaultBucketCount);
	const(Token)[] tokenArray = getTokensForParser(cast(ubyte[]) request.sourceCode,
		config, &cache);
	auto allocator = scoped!(ASTAllocator)();
	Scope* completionScope = generateAutocompleteTrees(tokenArray, allocator);
	scope(exit) typeid(Scope).destroy(completionScope);

	static struct SearchResults
	{
		void put(DSymbol* symbol)
		{
			tree.insert(SearchResult(symbol));
		}

		static struct SearchResult
		{
			DSymbol* symbol;

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

	foreach (symbol; completionScope.symbols[])
	{
		symbol.getAllPartsNamed(request.searchName, results);
	}
	foreach (s; ModuleCache.getAllSymbols())
	{
		s.symbol.getAllPartsNamed(request.searchName, results);
	}

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

enum ImportKind
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
AutocompleteResponse dotCompletion(T)(T beforeTokens,
	const(Token)[] tokenArray, size_t cursorPosition)
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
		foreach (symbol; (cast() arraySymbols)[])
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
		Scope* completionScope = generateAutocompleteTrees(tokenArray, allocator);
		scope(exit) typeid(Scope).destroy(completionScope);
		response.setCompletions(completionScope, getExpression(beforeTokens),
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
	StringCache* cache, out const(Token)[] tokenArray)
{
	LexerConfig config;
	config.fileName = "";
	tokenArray = getTokensForParser(cast(ubyte[]) sourceCode, config, cache);
	auto sortedTokens = assumeSorted(tokenArray);
	return sortedTokens.lowerBound(cast(size_t) cursorPosition);
}

struct ScopeSymbolPair
{
	~this()
	{
		if (scope_ !is null)
		{
			scope_.destroySymbols();
			typeid(Scope).destroy(scope_);
		}
	}

	DSymbol*[] symbols;
	Scope* scope_;
}

/**
 * Params:
 *     request = the autocompletion request
 *     type = type the autocompletion type
 * Returns:
 *     all symbols that should be considered for the autocomplete list based on
 *     the request's source code, cursor position, and completion type.
 */
ScopeSymbolPair getSymbolsForCompletion(const AutocompleteRequest request,
	const CompletionType type, IAllocator allocator, StringCache* cache)
{
	const(Token)[] tokenArray;
	auto beforeTokens = getTokensBeforeCursor(request.sourceCode,
		request.cursorPosition, cache, tokenArray);
	Scope* completionScope = generateAutocompleteTrees(tokenArray, allocator);
	auto expression = getExpression(beforeTokens);
	return ScopeSymbolPair(getSymbolsByTokenChain(completionScope, expression,
		request.cursorPosition, type), completionScope);
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
	const(Token)[] tokenArray, size_t cursorPosition)
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
		for (size_t i = 0; i < completions.length; i++)
		{
			response.completions ~= completions[i];
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
		Scope* completionScope = generateAutocompleteTrees(tokenArray, allocator);
		scope(exit) typeid(Scope).destroy(completionScope);
		auto expression = getExpression(beforeTokens[0 .. $ - 1]);
		response.setCompletions(completionScope, expression,
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
	if (!(tokens[i] == tok!":" || tokens[i] == tok!"," || tokens[i] == tok!"." || tokens[i] == tok!"identifier"))
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
AutocompleteResponse importCompletion(T)(T beforeTokens, ImportKind kind)
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

		while (beforeTokens[i].type != tok!"," && beforeTokens[i].type != tok!"import") i--;
		setImportCompletions(beforeTokens[i .. $], response);
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

	string path;
	{
		size_t k = 0;
		foreach (token; beforeTokens[i + 1 .. j])
		{
			if (token.type == tok!"identifier")
			{
				if (k != 0)
					path ~= "/";
				path ~= token.text;
			}
			k++;
		}
	}

	string resolvedLocation = ModuleCache.resolveImportLocation(path);
	if (resolvedLocation is null)
	{
		warning("Could not resolve location of ", path);
		return response;
	}
	auto symbols = ModuleCache.getModuleSymbol(resolvedLocation);

	import containers.hashset : HashSet;
	HashSet!string h;

	void addSymbolToResponses(DSymbol* sy)
	{
		auto a = DSymbol(sy.name);
		if (!builtinSymbols.contains(&a) && sy.name !is null && !h.contains(sy.name)
				&& sy.name != CONSTRUCTOR_SYMBOL_NAME)
		{
			response.completionKinds ~= sy.kind;
			response.completions ~= sy.name;
			h.insert(sy.name);
		}
	}

	foreach (s; symbols.opSlice())
	{
		if (s.kind == CompletionKind.importSymbol) foreach (sy; s.type.opSlice())
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
void setImportCompletions(T)(T tokens, ref AutocompleteResponse response)
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

	foreach (importDirectory; ModuleCache.getImportPaths())
	{
		string p = buildPath(importDirectory, path);
		if (!exists(p))
			continue;

		found = true;

		foreach (string name; dirEntries(p, SpanMode.shallow))
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
	}
	if (!found)
		warning("Could not find ", moduleParts);
}

/**
 *
 */
DSymbol*[] getSymbolsByTokenChain(T)(Scope* completionScope,
	T tokens, size_t cursorPosition, CompletionType completionType)
{
	// Find the symbol corresponding to the beginning of the chain
	DSymbol*[] symbols;
	if (tokens.length == 0)
		return [];
	if (tokens[0] == tok!"." && tokens.length > 1)
	{
		tokens = tokens[1 .. $];
		symbols = completionScope.getSymbolsAtGlobalScope(stringToken(tokens[0]));
	}
	else
		symbols = completionScope.getSymbolsByNameAndCursor(stringToken(tokens[0]), cursorPosition);

	if (symbols.length == 0)
	{
		warning("Could not find declaration of ", stringToken(tokens[0]),
			" from position ", cursorPosition);
		return [];
	}

	if (shouldSwapWithType(completionType, symbols[0].kind, 0, tokens.length - 1))
	{
		symbols = symbols[0].type is null ? [] : [symbols[0].type];
		if (symbols.length == 0)
			return symbols;
	}

	loop: for (size_t i = 1; i < tokens.length; i++)
	{
		IdType open;
		IdType close;
		void skip()
		{
			i++;
			for (int depth = 1; depth > 0 && i < tokens.length; i++)
			{
				if (tokens[i].type == open)
					depth++;
				else if (tokens[i].type == close)
				{
					depth--;
					if (depth == 0) break;
				}
			}
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
			// Use function return type instead of the function itself
			if (symbols[0].qualifier == SymbolQualifier.func
				|| symbols[0].kind == CompletionKind.functionName)
			{
				symbols = symbols[0].type is null ? [] :[symbols[0].type];
				if (symbols.length == 0)
					break loop;
			}

//			Log.trace("looking for ", tokens[i].text, " in ", symbols[0].name);
			symbols = symbols[0].getPartsByName(internString(tokens[i].text));
			if (symbols.length == 0)
			{
//				Log.trace("Couldn't find it.");
				break loop;
			}
			if (shouldSwapWithType(completionType, symbols[0].kind, i,
				tokens.length - 1))
			{
				symbols = symbols[0].type is null ? [] : [symbols[0].type];
				if (symbols.length == 0)
					break loop;
			}
			if (symbols[0].kind == CompletionKind.aliasName
				&& (completionType == CompletionType.identifiers
				|| i + 1 < tokens.length))
			{
				symbols = symbols[0].type is null ? [] : [symbols[0].type];
			}
			if (symbols.length == 0)
				break loop;
			break;
		case tok!"(":
			open = tok!"(";
			close = tok!")";
			skip();
			break;
		case tok!"[":
			open = tok!"[";
			close = tok!"]";
			if (symbols[0].qualifier == SymbolQualifier.array)
			{
				auto h = i;
				skip();
				Parser p = new Parser();
				p.setTokens(tokens[h .. i].array());
				if (!p.isSliceExpression())
				{
					symbols = symbols[0].type is null ? [] : [symbols[0].type];
					if (symbols.length == 0)
						break loop;
				}
			}
			else if (symbols[0].qualifier == SymbolQualifier.assocArray)
			{
				symbols = symbols[0].type is null ? [] : [symbols[0].type];
				skip();
			}
			else
			{
				auto h = i;
				skip();
				Parser p = new Parser();
				p.setTokens(tokens[h .. i].array());
				DSymbol*[] overloads;
				if (p.isSliceExpression())
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
	// Handle the simple case where we get all symbols in scope and filter it
	// based on the currently entered text.
	if (partial !is null && tokens.length == 0)
	{
		foreach (s; completionScope.getSymbolsInCursorScope(cursorPosition)
			.filter!(a => a.name.toUpper().startsWith(partial.toUpper())))
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
		if (symbols[0].qualifier == SymbolQualifier.func
			|| symbols[0].kind == CompletionKind.functionName)
		{
			symbols = symbols[0].type is null ? [] : [symbols[0].type];
			if (symbols.length == 0)
				return;
		}
		foreach (sym; symbols[0].opSlice())
		{
			if (sym.kind == CompletionKind.importSymbol) foreach (s; sym.type.opSlice())
			{
				response.completionKinds ~= s.kind;
				response.completions ~= s.name.dup;
			}
			else if (sym.name !is null && sym.name.length > 0 && sym.name[0] != '*'
				&& (partial is null ? true : sym.name.toUpper().startsWith(partial.toUpper()))
				&& !response.completions.canFind(sym.name))
			{
				response.completionKinds ~= sym.kind;
				response.completions ~= sym.name.dup;
			}
		}
		response.completionType = CompletionType.identifiers;
	}
	else if (completionType == CompletionType.calltips)
	{
//		Log.trace("Showing call tips for ", symbols[0].name, " of kind ", symbols[0].kind);
		if (symbols[0].kind != CompletionKind.functionName
			&& symbols[0].callTip is null)
		{
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
	assert (symbol.kind == CompletionKind.structName);
}
body
{
	string generatedStructConstructorCalltip = "this(";
	size_t i = 0;
	immutable c = count(symbol.opSlice().filter!(a => a.kind == CompletionKind.variableName));
	foreach (part; array(symbol.opSlice()).sort!((a, b) => a.location < b.location))
	{
		if (part.kind != CompletionKind.variableName)
			continue;
		i++;
		if (part.type !is null)
		{
			generatedStructConstructorCalltip ~= part.type.name;
			generatedStructConstructorCalltip ~= " ";
		}
		generatedStructConstructorCalltip ~= part.name;
		if (i < c)
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
			break expressionLoop;
		mixin (TYPE_IDENT_AND_LITERAL_CASES);
			mixin (EXPRESSION_LOOP_BREAK);
			if (i > 1 && beforeTokens[i - 1] == tok!"!"
				&& beforeTokens[i - 2] == tok!"identifier")
			{
				sliceEnd -= 2;
				i--;
			}
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
	// Modules and packages never have types, so always return false
	if (kind == CompletionKind.moduleName
		|| kind == CompletionKind.packageName
		|| kind == CompletionKind.className
		|| kind == CompletionKind.structName
		|| kind == CompletionKind.interfaceName
		|| kind == CompletionKind.enumName
		|| kind == CompletionKind.unionName)
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
		|| kind == CompletionKind.enumMember
		|| kind == CompletionKind.functionName;
	return isInteresting && (completionType == CompletionType.identifiers
		|| (completionType == completionType.calltips && kind == CompletionKind.variableName)) ;
}

/**
 * Params:
 *     comment = the comment to format
 * Returns
 *     the comment with the comment characters removed
 */
string formatComment(string comment)
{
	import std.regex : replaceFirst, replaceAll, regex;
	enum tripleSlashRegex = `(?:\t )*///`;
	enum slashStarRegex = `(?:^/\*\*+)|(?:\n?\s*\*+/$)|(?:(?<=\n)\s*\* ?)`;
	enum slashPlusRegex = `(?:^/\+\++)|(?:\n?\s*\++/$)|(?:(?<=\n)\s*\+ ?)`;
	if (comment.length < 3)
		return null;
	string re;
	if (comment[0 .. 3] == "///")
		re = tripleSlashRegex;
	else if (comment[1] == '+')
		re = slashPlusRegex;
	else
		re = slashStarRegex;
	return (comment.replaceAll(regex(re), ""))
		.replaceFirst(regex("^\n"), "")
		.replaceAll(regex(`\\`), `\\`)
		.replaceAll(regex("\n"), `\n`).outdent();
}

istring stringToken()(auto ref const Token a)
{
	return internString(a.text is null ? str(a.type) : a.text);
}
