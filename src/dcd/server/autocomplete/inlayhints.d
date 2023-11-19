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

module dcd.server.autocomplete.inlayhints;

import std.stdio;
import std.algorithm;
import std.array;
import std.experimental.allocator;
import std.experimental.logger;
import std.typecons;

import dcd.server.autocomplete.util;

import dparse.lexer;
import dparse.rollback_allocator;

import dsymbol.modulecache;
import dsymbol.symbol;
import dsymbol.scope_;
import dsymbol.conversion;
import dsymbol.string_interning;

import dcd.common.messages;

import containers.hashset;

public AutocompleteResponse getInlayHints(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
//	trace("Getting inlay hints comments");
	AutocompleteResponse response;

	LexerConfig config;
	config.fileName = "";
	auto cache = StringCache(request.sourceCode.length.optimalBucketCount);
	auto tokenArray = getTokensForParser(cast(ubyte[]) request.sourceCode, config, &cache);
	RollbackAllocator rba;
	auto pair = generateAutocompleteTrees(tokenArray, &rba, -1, moduleCache);
	scope(exit) pair.destroy();

	void check(DSymbol* it, ref HashSet!size_t visited)
	{
		if (visited.contains(cast(size_t) it))
			return;
		if (it.symbolFile != "stdin") return;
		visited.insert(cast(size_t) it);

		//writeln("sym: ", it.name," ", it.location, " kind: ", it.kind," qualifier: ", it.qualifier);
		//if (auto type = it.type)
		//{
		//	writeln("   ", type.name, " kind: ", type.kind, " qualifier", type.qualifier);
		//	if (auto ttype = type.type)
		//		writeln("      ", ttype.name, " kind: ", ttype.kind, " qualifier", ttype.qualifier);
		//}


		// aliases
		// 		struct Data {}
		// 		alias Alias1 = Data;
		// 		Alias1 var;				becomes:  Alias1 [-> Data] var;
		if (it.kind == CompletionKind.variableName && it.type && it.type.kind == CompletionKind.aliasName)
		{
			AutocompleteResponse.Completion c;
			c.symbolLocation = it.location - 1;

			DSymbol* type = it.type;

			while (type)
			{
				if (type.kind == CompletionKind.aliasName && type.type)
					c.identifier ~= "->" ~ type.type.name;
				if (type.type && type.type.kind != CompletionKind.aliasName) break;
				type = type.type;
			}

			response.completions ~= c;
		}

		foreach(part; it.opSlice())
			check(part, visited);
	}

	HashSet!size_t visited;
	foreach (symbol; pair.scope_.symbols)
	{
		check(symbol, visited);
		foreach(part; symbol.opSlice())
			check(part, visited);
	}
	return response;
}
