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
import std.d.ast;
import std.d.lexer;
import std.d.parser;
import std.range;
import std.stdio;
import std.uni;

import messages;
import importutils;
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
        switch (beforeTokens[$ - 2].type)
        {
        case TokenType.traits:
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < traits.length; i++)
            {
                response.completions ~= traits[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
            break;
        case TokenType.scope_:
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < scopes.length; i++)
            {
                response.completions ~= scopes[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
			break;
        case TokenType.version_:
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < versions.length; i++)
            {
                response.completions ~= versions[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
            break;
		case TokenType.extern_:
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < linkages.length; i++)
            {
                response.completions ~= linkages[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
            break;
        case TokenType.pragma_:
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < pragmas.length; i++)
            {
                response.completions ~= pragmas[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
            break;
        case TokenType.identifier:
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
            // TODO: This is a placeholder
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < allProperties.length; i++)
            {
                response.completions ~= allProperties[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
            break;
        case TokenType.lParen:
        case TokenType.lBrace:
        case TokenType.lBracket:
        case TokenType.semicolon:
        case TokenType.colon:
            // TODO: global scope
            break;
        case TokenType.rParen:
        case TokenType.rBrace:
        case TokenType.rBracket:
        default:
            // TODO
            break;
        }
    }
    else if (beforeTokens[$ - 1] == TokenType.identifier)
    {
        Module mod = parseModule(tokenArray, request.fileName, &messageFunction);

        writeln("Resolved imports: ", getImportedFiles(mod, importPaths ~ request.importPaths));
    }

    return response;
}

void messageFunction(string fileName, int line, int column, string message)
{
    // does nothing
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

enum SymbolKind
{
    className,
    interfaceName,
    enumName,
    variableName,
    structName,
    unionName,
    functionName
}

class Symbol
{
    Symbol[] parts;
    string name;
    SymbolKind kind;
    Type[string] templateParameters;
}

class Scope
{
public:
    /**
     * @return the innermost Scope that contains the given cursor position.
     */
    const(Scope) findCurrentScope(size_t cursorPosition) const
    {
        if (cursorPosition < start || cursorPosition > end)
            return null;
        foreach (sc; children)
        {
            auto s = sc.findCurrentScope(cursorPosition);
            if (s is null)
                continue;
            else
                return s;
        }
        return this;
    }

    const(Symbol)[] getSymbolsInScope() const
    {
        return symbols ~ parent.getSymbolsInScope();
    }


    Symbol[] getSymbolsInScope(string name)
    {
        Symbol[] results;
        symbols.filter!(x => x.name == name)().copy(results);
        parent.getSymbolsInScope(name).copy(results);
        return results;
    }

private:
    size_t start;
    size_t end;
    Symbol[] symbols;
    Scope parent;
    Scope[] children;
}
