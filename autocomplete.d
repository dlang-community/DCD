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
import stdx.d.ast;
import stdx.d.lexer;
import stdx.d.parser;
import std.range;
import std.stdio;
import std.uni;

import messages;
import acvisitor;
import actypes;
import constants;


AutocompleteResponse complete(AutocompleteRequest request, string[] importPaths)
{
    writeln("Got a completion request");
    AutocompleteResponse response;

    LexerConfig config;
    auto tokens = request.sourceCode.byToken(config);
    auto tokenArray = tokens.array();
    auto sortedTokens = assumeSorted(tokenArray);

    auto beforeTokens = sortedTokens.lowerBound(cast(size_t) request.cursorPosition);
    if (beforeTokens[$ - 1] ==  TokenType.lParen && beforeTokens.length >= 2)
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
			auto expression = getExpression(beforeTokens[0..$]);
            writeln("Expression: ", expression.map!"a.value"());
			response.completionType = CompletionType.calltips;
            // TODO
            break;
        default:
            break;
        }
    }
    else if (beforeTokens[$ - 1] ==  TokenType.dot && beforeTokens.length >= 2)
    {
        switch (beforeTokens[$ - 2].type)
        {
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
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < integerProperties.length; i++)
            {
                response.completions ~= integerProperties[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
            break;
        case TokenType.float_:
        case TokenType.ifloat_:
        case TokenType.cfloat_:
        case TokenType.idouble_:
        case TokenType.cdouble_:
        case TokenType.double_:
        case TokenType.real_:
        case TokenType.ireal_:
        case TokenType.creal_:
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < floatProperties.length; i++)
            {
                response.completions ~= floatProperties[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
            break;
        case TokenType.stringLiteral:
        case TokenType.wstringLiteral:
        case TokenType.dstringLiteral:
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < arrayProperties.length; i++)
            {
                response.completions ~= arrayProperties[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
            break;
        case TokenType.identifier:
        case TokenType.rParen:
        case TokenType.rBracket:
			auto visitor = processModule(tokenArray);
            auto expression = getExpression(beforeTokens[0..$]);
			response.setCompletions(visitor, expression, request.cursorPosition);
            break;
        case TokenType.lParen:
        case TokenType.lBrace:
        case TokenType.lBracket:
        case TokenType.semicolon:
        case TokenType.colon:
            // TODO: global scope
            break;
        default:
            // TODO
            break;
        }
    }
    return response;
}

void setCompletions(T)(ref AutocompleteResponse response,
	ref const AutoCompleteVisitor visitor, T tokens, size_t cursorPosition)
{
	// TODO: Completely hacked together.
	if (tokens[0] != TokenType.identifier) return;
	writeln("Getting completions for ", tokens[0].value);
	auto symbol = visitor.scope_.findSymbolInCurrentScope(cursorPosition, tokens[0].value);
	if (symbol is null)
		return;
	foreach (s; symbol.parts)
	{
		writeln("Adding ", s.name, " to the completion list");
		response.completionKinds ~= s.kind;
		response.completions ~= s.name;
	}
	response.completionType = CompletionType.identifiers;
}

T getExpression(T)(T beforeTokens)
{
	size_t i = beforeTokens.length - 1;
	TokenType open;
	TokenType close;
	bool hasSpecialPrefix = false;
	expressionLoop: while (true)
	{
		with (TokenType) switch (beforeTokens[i].type)
		{
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
		case bitAnd:
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
	return beforeTokens[i .. $ - 1];
}

string createCamelCaseRegex(string input)
{
    dstring output;
    uint i;
    foreach (dchar d; input)
    {
        if (isLower(d))
            output ~= d;
        else if (i > 0)
        {
            output ~= ".*";
            output ~= d;
        }
        i++;
    }
    return to!string(output ~ ".*");
}

unittest
{
    assert("ClNa".createCamelCaseRegex() == "Cl.*Na.*");
}
