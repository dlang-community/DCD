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

module server.autocomplete.doc;

import std.algorithm;
import std.array;
import std.experimental.logger;
import std.typecons;

import server.autocomplete.util;

import dparse.lexer;
import dparse.rollback_allocator;

import dsymbol.modulecache;

import common.messages;

/**
 * Gets documentation for the symbol at the cursor
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
public AutocompleteResponse getDoc(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
//	trace("Getting doc comments");
	AutocompleteResponse response;
	RollbackAllocator rba;
	auto allocator = scoped!(ASTAllocator)();
	auto cache = StringCache(StringCache.defaultBucketCount);
	SymbolStuff stuff = getSymbolsForCompletion(request, CompletionType.ddoc,
		allocator, &rba, cache, moduleCache);
	if (stuff.symbols.length == 0)
		warning("Could not find symbol");
	else
	{
		Appender!(char[]) app;

		bool isDitto(string s)
		{
			import std.uni : icmp;
			if (s.length > 5)
				return false;
			else
				return s.icmp("ditto") == 0;
		}

		void putDDocChar(char c)
		{
			switch (c)
			{
			case '\\':
				app.put('\\');
				app.put('\\');
				break;
			case '\n':
				app.put('\\');
				app.put('n');
				break;
			default:
				app.put(c);
				break;
			}
		}

		void putDDocString(string s)
		{
			foreach (char c; s)
				putDDocChar(c);
		}

		foreach(ref symbol; stuff.symbols.filter!(a => !a.doc.empty && !isDitto(a.doc)))
		{
			app.clear;
			putDDocString(symbol.doc);
			response.docComments ~= app.data.idup;
		}
	}
	return response;
}