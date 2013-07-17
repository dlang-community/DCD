module autocomplete;

import std.array;
import std.stdio;
import std.d.lexer;
import std.d.parser;
import std.d.ast;
import std.range;

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
    if (beforeTokens[$ - 1] ==  TokenType.lParen)
    {
        if (beforeTokens[$ - 2] == TokenType.traits)
        {
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < traits.length; i++)
            {
                response.completions ~= traits[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
        }
        else if (beforeTokens[$ - 2] == TokenType.scope_)
        {
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < scopes.length; i++)
            {
                response.completions ~= scopes[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
        }
        else if (beforeTokens[$ - 2] == TokenType.version_)
        {
            response.completionType = CompletionType.identifiers;
            for (size_t i = 0; i < versions.length; i++)
            {
                response.completions ~= versions[i];
                response.completionKinds ~= CompletionKind.keyword;
            }
        }
    }
    else
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
