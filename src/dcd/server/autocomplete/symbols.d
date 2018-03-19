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

module dcd.server.autocomplete.symbols;

import std.experimental.logger;
import std.typecons;

import dcd.server.autocomplete.util;

import dparse.lexer;
import dparse.rollback_allocator;

import dsymbol.conversion;
import dsymbol.modulecache;
import dsymbol.string_interning;
import dsymbol.symbol;

import dcd.common.messages;

import containers.hashset;

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

			int opCmp(ref const SearchResult other) const pure nothrow @nogc @safe
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
		response.completions ~= makeSymbolCompletionInfo(result.symbol, result.symbol.kind);

	return response;
}
