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

module autocomplete;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.path;
import std.range;
import std.stdio;
import std.uni;
import std.d.ast;
import std.d.lexer;
import std.d.parser;
import std.string;
import std.typecons;
import memory.allocators;
import std.allocator;

import messages;
import actypes;
import constants;
import modulecache;
import conversion.astconverter;
import stupidlog;

/**
 * Gets documentation for the symbol at the cursor
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
AutocompleteResponse getDoc(const AutocompleteRequest request)
{
	Log.trace("Getting doc comments");
	AutocompleteResponse response;
	auto allocator = scoped!(CAllocatorImpl!(BlockAllocator!(1024 * 16)))();
	auto cache = StringCache(StringCache.defaultBucketCount);
	ACSymbol*[] symbols = getSymbolsForCompletion(request, CompletionType.ddoc,
		allocator, &cache);
	if (symbols.length == 0)
		Log.error("Could not find symbol");
	else foreach (symbol; symbols)
	{
		if (symbol.doc is null)
		{
			Log.trace("Doc comment for ", symbol.name, " was null");
			continue;
		}
		Log.trace("Adding doc comment for ", symbol.name, ": ", symbol.doc);
		response.docComments ~= formatComment(symbol.doc);
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
AutocompleteResponse findDeclaration(const AutocompleteRequest request)
{
	Log.trace("Finding declaration");
	AutocompleteResponse response;
	auto allocator = scoped!(CAllocatorImpl!(BlockAllocator!(1024 * 16)))();
	auto cache = StringCache(StringCache.defaultBucketCount);
	ACSymbol*[] symbols = getSymbolsForCompletion(request,
		CompletionType.location, allocator, &cache);
	if (symbols.length > 0)
	{
		response.symbolLocation = symbols[0].location;
		response.symbolFilePath = symbols[0].symbolFile.idup;
		Log.info(symbols[0].name, " declared in ",
			response.symbolFilePath, " at ", response.symbolLocation);
	}
	else
		Log.error("Could not find symbol");
	return response;
}

/**
 * Handles autocompletion
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
AutocompleteResponse complete(const AutocompleteRequest request)
{
	Log.info("Got a completion request");

	const(Token)[] tokenArray;
	auto cache = StringCache(StringCache.defaultBucketCount);
	auto beforeTokens = getTokensBeforeCursor(request.sourceCode,
		request.cursorPosition, &cache, tokenArray);
	string partial;
	IdType tokenType;

	if (beforeTokens.length >= 2 && (beforeTokens[$ - 1] == tok!"("
		|| beforeTokens[$ - 1] == tok!"["))
	{
		return parenCompletion(beforeTokens, tokenArray, request.cursorPosition);
	}

	AutocompleteResponse response;
	if (beforeTokens.length >= 1 && beforeTokens[$ - 1] == tok!"identifier")
	{
		partial = beforeTokens[$ - 1].text;
		tokenType = beforeTokens[$ - 1].type;
		beforeTokens = beforeTokens[0 .. $ - 1];
	}
	else if (beforeTokens.length >= 2 && beforeTokens[$ - 1] ==  tok!".")
		tokenType = beforeTokens[$ - 2].type;
	else
		return response;
	auto allocator = scoped!(CAllocatorImpl!(BlockAllocator!(1024 * 16)))();
	switch (tokenType)
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
		auto semanticAllocator = scoped!(CAllocatorImpl!(BlockAllocator!(1024*16)));
		Scope* completionScope = generateAutocompleteTrees(tokenArray,
			"stdin", allocator, semanticAllocator);
		scope(exit) typeid(Scope).destroy(completionScope);
		response.setCompletions(completionScope, getExpression(beforeTokens),
			request.cursorPosition, CompletionType.identifiers, false, partial);
		break;
	case tok!"(":
	case tok!"{":
	case tok!"[":
	case tok!";":
	case tok!":":
		// TODO: global scope
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
	config.fileName = "stdin";
	auto tokens = byToken(cast(ubyte[]) sourceCode, config, cache);
	tokenArray = tokens.array();
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
ACSymbol*[] getSymbolsForCompletion(const AutocompleteRequest request,
	const CompletionType type, CAllocator allocator, StringCache* cache)
{
	const(Token)[] tokenArray;
	auto beforeTokens = getTokensBeforeCursor(request.sourceCode,
		request.cursorPosition, cache, tokenArray);
	auto semanticAllocator = scoped!(CAllocatorImpl!(BlockAllocator!(1024*16)));
	Scope* completionScope = generateAutocompleteTrees(tokenArray,
		"stdin", allocator, semanticAllocator);
	scope(exit) typeid(Scope).destroy(completionScope);
	auto expression = getExpression(beforeTokens);
	return getSymbolsByTokenChain(completionScope, expression,
		request.cursorPosition, type);
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
	auto allocator = scoped!(CAllocatorImpl!(BlockAllocator!(1024 * 16)))();
	switch (beforeTokens[$ - 2].type)
	{
	case tok!"__traits":
		completions = traits;
		goto fillResponse;
	case tok!"scope":
		completions = scopes;
		goto fillResponse;
	case tok!"version":
		completions = versions;
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
	case tok!"identifier":
	case tok!")":
	case tok!"]":
		auto semanticAllocator = scoped!(CAllocatorImpl!(BlockAllocator!(1024*16)));
		Scope* completionScope = generateAutocompleteTrees(tokenArray,
			"stdin", allocator, semanticAllocator);
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
 *
 */
ACSymbol*[] getSymbolsByTokenChain(T)(Scope* completionScope,
	T tokens, size_t cursorPosition, CompletionType completionType)
{
	import std.d.lexer;
	Log.trace("Getting symbols from token chain",
		tokens.map!stringToken);
	// Find the symbol corresponding to the beginning of the chain
	ACSymbol*[] symbols = completionScope.getSymbolsByNameAndCursor(
		stringToken(tokens[0]), cursorPosition);
	if (symbols.length == 0)
	{
		Log.error("Could not find declaration of ", stringToken(tokens[0]),
			" from position ", cursorPosition);
		return [];
	}
	else
	{
		Log.trace("Found ", symbols[0].name, " at ", symbols[0].location,
			" with type ", symbols[0].type is null ? "null" : symbols[0].type.name);
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
			symbols = symbols[0].getPartsByName(str(tokens[i].type));
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

			Log.trace("looking for ", tokens[i].text, " in ", symbols[0].name);
			symbols = symbols[0].getPartsByName(tokens[i].text);
			if (symbols.length == 0)
			{
				Log.trace("Couldn't find it.");
				break loop;
			}
			if (shouldSwapWithType(completionType, symbols[0].kind, i,
				tokens.length - 1))
			{
				symbols = symbols[0].type is null ? [] : [symbols[0].type];
			}
			if (symbols.length == 0)
				break loop;
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
				}
			}
			else if (symbols[0].qualifier == SymbolQualifier.assocArray)
			{
				symbols = symbols[0].type is null ? [] :[symbols[0].type];
				skip();
			}
			else
			{
				auto h = i;
				skip();
				Parser p = new Parser();
				p.setTokens(tokens[h .. i].array());
				ACSymbol*[] overloads;
				if (p.isSliceExpression())
					overloads = symbols[0].getPartsByName("opSlice");
				else
					overloads = symbols[0].getPartsByName("opIndex");
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
	// Autocomplete module imports instead of symbols
	if (tokens.length > 0 && tokens[0].type == tok!"import")
	{
		if (completionType == CompletionType.identifiers)
			setImportCompletions(tokens, response);
		return;
	}

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

	ACSymbol*[] symbols = getSymbolsByTokenChain(completionScope, tokens,
		cursorPosition, completionType);

	if (symbols.length == 0)
		return;

	if (completionType == CompletionType.identifiers)
	{
		if (symbols[0].qualifier == SymbolQualifier.func
			|| symbols[0].kind == CompletionKind.functionName)
		{
			Log.trace("Completion list for return type of function ", symbols[0].name);
			symbols = symbols[0].type is null ? [] : [symbols[0].type];
			if (symbols.length == 0)
				return;
		}
		foreach (s; symbols[0].parts[].filter!(a => a.name !is null
			&& a.name.length > 0 && a.name[0] != '*'
			&& (partial is null ? true : a.name.toUpper().startsWith(partial.toUpper()))
			&& !response.completions.canFind(a.name)))
		{
//			Log.trace("Adding ", s.name, " to the completion list");
			response.completionKinds ~= s.kind;
			response.completions ~= s.name.dup;
		}
		response.completionType = CompletionType.identifiers;
	}
	else if (completionType == CompletionType.calltips)
	{
		Log.trace("Showing call tips for ", symbols[0].name, " of type ", symbols[0].kind);
		if (symbols[0].kind != CompletionKind.functionName
			&& symbols[0].callTip is null)
		{
			if (symbols[0].kind == CompletionKind.variableName)
			{
				auto dumb = symbols[0].type;
				if (isBracket)
				{
					auto index = dumb.getPartsByName("opIndex");
					if (index.length > 0)
					{
						symbols = index;
						goto setCallTips;
					}
				}
				auto call = dumb.getPartsByName("opCall");
				if (call.length > 0)
				{
					symbols = call;
					goto setCallTips;
				}
			}
			if (symbols[0].kind == CompletionKind.structName
				|| symbols[0].kind == CompletionKind.className)
			{
				auto constructor = symbols[0].getPartsByName("*constructor*");
				if (constructor.length == 0)
					return;
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
			if (symbol.kind != CompletionKind.aliasName)
				response.completions ~= symbol.callTip;
		}
	}
}

/**
 *
 */
T getExpression(T)(T beforeTokens)
{
	if (beforeTokens.length == 0)
		return beforeTokens[0 .. 0];
	size_t i = beforeTokens.length - 1;
	IdType open;
	IdType close;
	expressionLoop: while (true)
	{
		switch (beforeTokens[i].type)
		{
		case tok!"import":
			break expressionLoop;
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
		case tok!"identifier":
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
			auto bookmark = i;
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
	return beforeTokens[i .. $];
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
	auto moduleParts = tokens.filter!(a => a.type == tok!"identifier").map!("a.text").array();
	if (moduleParts.length == 0)
		return;
	string path = buildPath(moduleParts);
	foreach (importDirectory; ModuleCache.getImportPaths())
	{
		string p = buildPath(importDirectory, path);
		Log.trace("Checking for ", p);
		if (!exists(p))
			continue;
		foreach (string name; dirEntries(p, SpanMode.shallow))
		{
			if (isFile(name) && (name.endsWith(".d") || name.endsWith(".di")))
			{
				response.completions ~= name.baseName(".d").baseName(".di");
				response.completionKinds ~= CompletionKind.moduleName;
			}
			else if (isDir(name))
			{
				response.completions ~= name.baseName();
				response.completionKinds ~=
					exists(buildPath(name, "package.d")) || exists(buildPath(name, "package.di"))
					? CompletionKind.moduleName : CompletionKind.packageName;
			}
		}
	}
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
	return completionType == CompletionType.identifiers && isInteresting;
}

/**
 * Params:
 *     comment = the comment to format
 * Returns
 *     the comment with the comment characters removed
 */
string formatComment(string comment)
{
	import std.string;
	import std.regex;
	enum tripleSlashRegex = `(?:\t )*///`;
	enum slashStarRegex = `(?:^/\*\*+)|(?:\n?\s*\*+/$)|(?:(?<=\n)\s*\* ?)`;
	enum slashPlusRegex = `(?:^/\+\++)|(?:\n?\s*\++/$)|(?:(?<=\n)\s*\+ ?)`;
	if (comment is null)
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

string stringToken()(auto ref const Token a)
{
	return a.text is null ? str(a.type) : a.text;
}

//unittest
//{
//	auto comment1 = "/**\n * This is some text\n */";
//	auto result1 = formatComment(comment1);
//	assert (result1 == `This is some text\n\n`, result1);
//
//	auto comment2 = "///some\n///text";
//	auto result2 = formatComment(comment2);
//	assert (result2 == `some\ntext\n\n`, result2);
//}
