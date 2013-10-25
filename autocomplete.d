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
	Log.info("Finding declaration");
	AutocompleteResponse response;
	LexerConfig config;
	config.fileName = "stdin";
	auto tokens = byToken(cast(ubyte[]) request.sourceCode, config);
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

	Log.info("Token at cursor: ", beforeTokens[$ - 1]);

	const(Scope)* completionScope = generateAutocompleteTrees(tokenArray, "stdin");
	auto expression = getExpression(beforeTokens);

	const(ACSymbol)*[] symbols = getSymbolsByTokenChain(completionScope, expression,
		request.cursorPosition, CompletionType.identifiers);

	if (symbols.length > 0)
	{
		response.symbolLocation = symbols[0].location;
		response.symbolFilePath = symbols[0].symbolFile;
		Log.info(beforeTokens[$ - 1].value, " declared in ",
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
	// Find the symbol corresponding to the beginning of the chain
	const(ACSymbol)*[] symbols = completionScope.getSymbolsByNameAndCursor(
		tokens[0].value, cursorPosition);
	if (symbols.length == 0)
	{
		Log.trace("Could not find declaration of ", tokens[0].value);
		return [];
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
		TokenType open;
		TokenType close;
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
		with (TokenType) switch (tokens[i].type)
		{
		case int_:
		case uint_:
		case long_:
		case ulong_:
		case char_:
		case wchar_:
		case dchar_:
		case bool_:
		case byte_:
		case ubyte_:
		case short_:
		case ushort_:
		case cent_:
		case ucent_:
		case float_:
		case ifloat_:
		case cfloat_:
		case idouble_:
		case cdouble_:
		case double_:
		case real_:
		case ireal_:
		case creal_:
		case this_:
			symbols = symbols[0].getPartsByName(getTokenValue(tokens[i].type));
			if (symbols.length == 0)
				break loop;
			break;
		case identifier:
			Log.trace("looking for ", tokens[i].value, " in ", symbols[0].name);
			symbols = symbols[0].getPartsByName(tokens[i].value);
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
		case lParen:
			open = TokenType.lParen;
			close = TokenType.rParen;
			skip();
			break;
		case lBracket:
			open = TokenType.lBracket;
			close = TokenType.rBracket;
			if (symbols[0].qualifier == SymbolQualifier.array)
			{
				auto h = i;
				skip();
				Parser p;
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
				Parser p;
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
		case dot:
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
	auto tokens = byToken(cast(ubyte[]) request.sourceCode, config);
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

	TokenType tokenType;

	if (beforeTokens.length >= 1 && beforeTokens[$ - 1] == TokenType.identifier)
	{
		Log.trace("partial completion");
		partial = beforeTokens[$ - 1].value;
		tokenType = beforeTokens[$ - 1].type;
		beforeTokens = beforeTokens[0 .. $ - 1];
		goto dotCompletion;
	}
	if (beforeTokens.length >= 2 && beforeTokens[$ - 1] == TokenType.lParen)
	{
		immutable(string)[] completions;
		switch (beforeTokens[$ - 2].type)
		{
		case TokenType.traits:
			completions = traits;
			goto fillResponse;
		case TokenType.scope_:
			completions = scopes;
			goto fillResponse;
		case TokenType.version_:
			completions = versions;
			goto fillResponse;
		case TokenType.extern_:
			completions = linkages;
			goto fillResponse;
		case TokenType.pragma_:
			completions = pragmas;
		fillResponse:
			response.completionType = CompletionType.identifiers;
			for (size_t i = 0; i < completions.length; i++)
			{
				response.completions ~= completions[i];
				response.completionKinds ~= CompletionKind.keyword;
			}
			break;
		case TokenType.identifier:
		case TokenType.rParen:
		case TokenType.rBracket:
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
	else if (beforeTokens.length >= 2 && beforeTokens[$ - 1] ==  TokenType.dot)
	{
		tokenType = beforeTokens[$ - 2].type;
dotCompletion:
		switch (tokenType)
		{
		case TokenType.stringLiteral:
		case TokenType.wstringLiteral:
		case TokenType.dstringLiteral:
			foreach (symbol; arraySymbols)
			{
				response.completionKinds ~= symbol.kind;
				response.completions ~= symbol.name;
			}
			response.completionType = CompletionType.identifiers;
			break;
		case TokenType.int_:
		case TokenType.uint_:
		case TokenType.long_:
		case TokenType.ulong_:
		case TokenType.char_:
		case TokenType.wchar_:
		case TokenType.dchar_:
		case TokenType.bool_:
		case TokenType.byte_:
		case TokenType.ubyte_:
		case TokenType.short_:
		case TokenType.ushort_:
		case TokenType.cent_:
		case TokenType.ucent_:
		case TokenType.float_:
		case TokenType.ifloat_:
		case TokenType.cfloat_:
		case TokenType.idouble_:
		case TokenType.cdouble_:
		case TokenType.double_:
		case TokenType.real_:
		case TokenType.ireal_:
		case TokenType.creal_:
		case TokenType.identifier:
		case TokenType.rParen:
		case TokenType.rBracket:
		case TokenType.this_:
			const(Scope)* completionScope = generateAutocompleteTrees(tokenArray,
				"stdin");
			auto expression = getExpression(beforeTokens);
			response.setCompletions(completionScope, expression,
				request.cursorPosition, CompletionType.identifiers, partial);
			break;
		case TokenType.lParen:
		case TokenType.lBrace:
		case TokenType.lBracket:
		case TokenType.semicolon:
		case TokenType.colon:
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
	if (tokens.length > 0 && tokens[0].type == TokenType.import_)
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
			if (call.length == 0)
			{
				symbols = call;
				goto setCallTips;
			}
			auto constructor = symbols[0].getPartsByName("*constructor*");
			if (constructor.length == 0)
				return;
			else
			{
				symbols = constructor;
				goto setCallTips;
			}
		}
	setCallTips:
		response.completionType = CompletionType.calltips;
		foreach (symbol; symbols)
		{
			Log.trace("Adding calltip ", symbol.callTip);
			response.completions ~= symbol.callTip;
		}
	}
}

T getExpression(T)(T beforeTokens)
{
	if (beforeTokens.length == 0)
		return beforeTokens[0 .. 0];
	size_t i = beforeTokens.length - 1;
	TokenType open;
	TokenType close;
	bool hasSpecialPrefix = false;
	expressionLoop: while (true)
	{
		with (TokenType) switch (beforeTokens[i].type)
		{
		case TokenType.import_:
			break expressionLoop;
		case TokenType.int_:
		case TokenType.uint_:
		case TokenType.long_:
		case TokenType.ulong_:
		case TokenType.char_:
		case TokenType.wchar_:
		case TokenType.dchar_:
		case TokenType.bool_:
		case TokenType.byte_:
		case TokenType.ubyte_:
		case TokenType.short_:
		case TokenType.ushort_:
		case TokenType.cent_:
		case TokenType.ucent_:
		case TokenType.float_:
		case TokenType.ifloat_:
		case TokenType.cfloat_:
		case TokenType.idouble_:
		case TokenType.cdouble_:
		case TokenType.double_:
		case TokenType.real_:
		case TokenType.ireal_:
		case TokenType.creal_:
		case this_:
		case identifier:
			if (hasSpecialPrefix)
			{
				i++;
				break expressionLoop;
			}
			break;
		case dot:
			break;
		case star:
		case amp:
			hasSpecialPrefix = true;
			break;
		case rParen:
			open = rParen;
			close = lParen;
			goto skip;
		case rBracket:
			open = rBracket;
			close = lBracket;
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
				case TokenType.if_:
				case TokenType.while_:
				case TokenType.for_:
				case TokenType.foreach_:
				case TokenType.foreach_reverse_:
				case TokenType.do_:
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
	auto moduleParts = tokens.filter!(a => a.type == TokenType.identifier).map!("a.value").array();
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
				response.completionKinds ~= CompletionKind.packageName;
			}
		}
	}
}
