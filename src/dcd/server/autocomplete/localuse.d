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

module dcd.server.autocomplete.localuse;

import std.experimental.allocator;
import std.experimental.logger;
import std.range;
import std.typecons;

import dcd.server.autocomplete.util;

import dparse.lexer;
import dparse.rollback_allocator;

import dsymbol.conversion;
import dsymbol.modulecache;
import dsymbol.symbol;
import dsymbol.utils;

import dcd.common.messages;

/**
 * Finds the uses of the symbol at the cursor position within a single document.
 * Params:
 *     request = the autocompletion request.
 * Returns:
 *     the autocompletion response.
 */
public AutocompleteResponse findLocalUse(AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
	AutocompleteResponse response;
	RollbackAllocator rba;
	auto cache = StringCache(request.sourceCode.length.optimalBucketCount);

	// patchs the original request for the subsequent requests
	request.kind = RequestKind.symbolLocation;

	// getSymbolsForCompletion() copy to avoid repetitive parsing
	LexerConfig config;
	config.fileName = "";
	const(Token)[] tokenArray = getTokensForParser(cast(ubyte[]) request.sourceCode,
			config, &cache);
	SymbolStuff getSymbolsAtCursor(size_t cursorPosition)
	{
		auto sortedTokens = assumeSorted(tokenArray);
		auto beforeTokens = sortedTokens.lowerBound(cursorPosition);
		ScopeSymbolPair pair = generateAutocompleteTrees(tokenArray,
			&rba, request.cursorPosition, moduleCache);
		auto expression = getExpression(beforeTokens);
		return SymbolStuff(getSymbolsByTokenChain(pair.scope_, expression,
			cursorPosition, CompletionType.location), pair.symbol, pair.scope_);
	}

	// gets the symbol matching to cursor pos
	SymbolStuff stuff = getSymbolsAtCursor(cast(size_t)request.cursorPosition);
	scope(exit) stuff.destroy();

	// starts searching only if no ambiguity with the symbol
	if (stuff.symbols.length == 1)
	{
		const(DSymbol*) sourceSymbol = stuff.symbols[0];
		response.symbolLocation = sourceSymbol.location;
		response.symbolFilePath = sourceSymbol.symbolFile.idup;

		// gets the source token to avoid too much getSymbolsAtCursor()
		const(Token)* sourceToken;
		foreach(i, t; tokenArray)
		{
			if (t.type != tok!"identifier")
				continue;
			if (request.cursorPosition > t.index &&
				request.cursorPosition <= t.index + t.text.length)
			{
				sourceToken = tokenArray.ptr + i;
				break;
			}
		}

		// finds the tokens that match to the source symbol
		if (sourceToken != null) foreach (t; tokenArray)
		{
			if (t.type == tok!"identifier" && t.text == sourceToken.text)
			{
				size_t pos = cast(size_t) t.index + 1; // place cursor inside the token
				SymbolStuff candidate = getSymbolsAtCursor(pos);
				scope(exit) candidate.destroy();
				if (candidate.symbols.length == 1 &&
					candidate.symbols[0].location == sourceSymbol.location &&
					candidate.symbols[0].symbolFile == sourceSymbol.symbolFile)
				{
					AutocompleteResponse.Completion c;
					c.symbolLocation = t.index;
					response.completions ~= c;
				}
			}
		}
		else
		{
			warning("The source token is not an identifier");
		}
	}
	else
	{
		warning("No or ambiguous symbol for the identifier at cursor");
	}
	return response;
}
