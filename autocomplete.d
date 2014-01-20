/*******************************************************************************
 * Authors: Brian Schott
 * Copyright: Brian Schott
 * Date: Jul 19 2013
 *
 * License:
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
 ******************************************************************************/

module autocomplete;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.path;
import std.range;
import std.stdio;
import std.uni;
import stdx.d.ast;
import stdx.d.lexer;
import stdx.d.parser;
import std.string;

import messages;
import actypes;
import constants;
import modulecache;
import astconverter;
import stupidlog;

AutocompleteResponse findDeclaration(const AutocompleteRequest request)
{
	Log.trace("Finding declaration");
	AutocompleteResponse response;
	LexerConfig config;
	config.fileName = "stdin";
	StringCache* cache = new StringCache(StringCache.defaultBucketCount);
	auto tokens = byToken(cast(ubyte[]) request.sourceCode, config, cache);
	const(Token)[] tokenArray = void;
	try {
		tokenArray = tokens.array();
	} catch (Exception e) {
		Log.error("Could not provide autocomplete due to lexing exception: ", e.msg);
		return response;
	}
	auto sortedTokens = assumeSorted(tokenArray);
	string partial;

	auto beforeTokens = sortedTokens.lowerBound(cast(size_t) request.cursorPosition);

	Log.trace("Token at cursor: ", beforeTokens[$ - 1]);

	const(Scope)* completionScope = generateAutocompleteTrees(tokenArray, "stdin");
	auto expression = getExpression(beforeTokens);

	const(ACSymbol)*[] symbols = getSymbolsByTokenChain(completionScope, expression,
		request.cursorPosition, CompletionType.identifiers);

	if (symbols.length > 0)
	{
		response.symbolLocation = symbols[0].location;
		response.symbolFilePath = symbols[0].symbolFile;
		Log.info(beforeTokens[$ - 1].text, " declared in ",
			response.symbolFilePath, " at ", response.symbolLocation);
	}
	else
	{
		Log.error("Could not find symbol");
	}

	return response;
}

const(ACSymbol)*[] getSymbolsByTokenChain(T)(const(Scope)* completionScope,
	T tokens, size_t cursorPosition, CompletionType completionType)
{
	Log.trace("Getting symbols from token chain", tokens);
	// Find the symbol corresponding to the beginning of the chain
	const(ACSymbol)*[] symbols = completionScope.getSymbolsByNameAndCursor(
		tokens[0].text, cursorPosition);
	if (symbols.length == 0)
	{
		Log.error("Could not find declaration of ", tokens[0].text,
			" from position ", cursorPosition);
		return [];
	}
	else
	{
		Log.trace("Found ", symbols[0].name, " at ", symbols[0].location,
			" with type ", symbols[0].type is null ? "null" : symbols[0].type.name);
	}

	if (completionType == CompletionType.identifiers
		&& symbols[0].kind == CompletionKind.memberVariableName
		|| symbols[0].kind == CompletionKind.variableName
		|| symbols[0].kind == CompletionKind.aliasName
		|| symbols[0].kind == CompletionKind.enumMember)
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
			if (symbols[0].kind == CompletionKind.variableName
				|| symbols[0].kind == CompletionKind.memberVariableName
				|| symbols[0].kind == CompletionKind.enumMember
				|| (symbols[0].kind == CompletionKind.functionName
				&& (completionType == CompletionType.identifiers
				|| i + 1 < tokens.length)))
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
				const(ACSymbol)*[] overloads;
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

AutocompleteResponse complete(const AutocompleteRequest request)
{
	Log.info("Got a completion request");
	AutocompleteResponse response;

	LexerConfig config;
	config.fileName = "stdin";
	StringCache* cache = new StringCache(StringCache.defaultBucketCount);
	auto tokens = byToken(cast(ubyte[]) request.sourceCode, config,
		cache);
	const(Token)[] tokenArray = void;
	try {
		tokenArray = tokens.array();
	} catch (Exception e) {
		Log.error("Could not provide autocomplete due to lexing exception: ", e.msg);
		return response;
	}
	auto sortedTokens = assumeSorted(tokenArray);
	string partial;

	auto beforeTokens = sortedTokens.lowerBound(cast(size_t) request.cursorPosition);

	IdType tokenType;

	if (beforeTokens.length >= 1 && beforeTokens[$ - 1] == tok!"identifier")
	{
		partial = beforeTokens[$ - 1].text;
		tokenType = beforeTokens[$ - 1].type;
		beforeTokens = beforeTokens[0 .. $ - 1];
		goto dotCompletion;
	}
	if (beforeTokens.length >= 2 && beforeTokens[$ - 1] == tok!"(")
	{
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
			const(Scope)* completionScope = generateAutocompleteTrees(tokenArray,
				"stdin");
			auto expression = getExpression(beforeTokens[0 .. $ - 1]);
			response.setCompletions(completionScope, expression,
				request.cursorPosition, CompletionType.calltips);
			break;
		default:
			break;
		}
	}
	else if (beforeTokens.length >= 2 && beforeTokens[$ - 1] ==  tok!".")
	{
		tokenType = beforeTokens[$ - 2].type;
dotCompletion:
		switch (tokenType)
		{
		case tok!"stringLiteral":
		case tok!"wstringLiteral":
		case tok!"dstringLiteral":
			foreach (symbol; arraySymbols)
			{
				response.completionKinds ~= symbol.kind;
				response.completions ~= symbol.name;
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
			const(Scope)* completionScope = generateAutocompleteTrees(tokenArray,
				"stdin");
			auto expression = getExpression(beforeTokens);
			response.setCompletions(completionScope, expression,
				request.cursorPosition, CompletionType.identifiers, partial);
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
	}
	return response;
}

void setCompletions(T)(ref AutocompleteResponse response,
	const(Scope)* completionScope, T tokens, size_t cursorPosition,
	CompletionType completionType, string partial = null)
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
			response.completions ~= s.name;
		}
		response.completionType = CompletionType.identifiers;
		return;
	}

	if (tokens.length == 0)
		return;

	const(ACSymbol)*[] symbols = getSymbolsByTokenChain(completionScope, tokens,
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
		foreach (s; symbols[0].parts.filter!(a => a.name !is null
			&& a.name[0] != '*'
			&& (partial is null ? true : a.name.toUpper().startsWith(partial.toUpper()))
			&& !response.completions.canFind(a.name)))
		{
			Log.trace("Adding ", s.name, " to the completion list");
			response.completionKinds ~= s.kind;
			response.completions ~= s.name;
		}
		response.completionType = CompletionType.identifiers;
	}
	else if (completionType == CompletionType.calltips)
	{
		Log.trace("Showing call tips for ", symbols[0].name, " of type ", symbols[0].kind);
		if (symbols[0].kind != CompletionKind.functionName
			&& symbols[0].callTip is null)
		{
			auto call = symbols[0].getPartsByName("opCall");
			if (call.length > 0)
			{
				symbols = call;
				goto setCallTips;
			}
			auto constructor = symbols[0].getPartsByName("*constructor*");
			if (constructor.length == 0)
				return;
			else
			{
				Log.trace("Not a function, but it has a constructor");
				symbols = constructor;
				goto setCallTips;
			}
		}
	setCallTips:
		response.completionType = CompletionType.calltips;
		foreach (symbol; symbols)
		{
			Log.trace("Adding calltip ", symbol.callTip);
			if (symbol.kind != CompletionKind.aliasName)
				response.completions ~= symbol.callTip;
		}
	}
}

T getExpression(T)(T beforeTokens)
{
	if (beforeTokens.length == 0)
		return beforeTokens[0 .. 0];
	size_t i = beforeTokens.length - 1;
	IdType open;
	IdType close;
	bool hasSpecialPrefix = false;
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
			if (hasSpecialPrefix)
			{
				i++;
				break expressionLoop;
			}
			break;
		case tok!".":
			break;
		case tok!"*":
		case tok!"&":
			hasSpecialPrefix = true;
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
					i = bookmark + 1;
					break expressionLoop;
				default:
					break;
			}
			break;
		default:
			if (hasSpecialPrefix)
				i++;
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

void setImportCompletions(T)(T tokens, ref AutocompleteResponse response)
{
	response.completionType = CompletionType.identifiers;
	auto moduleParts = tokens.filter!(a => a.type == tok!"identifier").map!("a.text").array();
	if (moduleParts.length == 0)
		return;
	string path = buildPath(moduleParts);
	foreach (importDirectory; ModuleCache.getImportPaths())
	{
		string p = format("%s%s%s", importDirectory, dirSeparator, path);
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
					? CompletionKind.packageName : CompletionKind.moduleName;
			}
		}
	}
}
