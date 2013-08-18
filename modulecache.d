/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2013 Brian Schott
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

module modulecache;

import std.file;
import std.datetime;
import stdx.d.lexer;
import stdx.d.parser;
import stdx.d.ast;
import std.stdio;
import std.array;
import std.path;
import std.algorithm;

import acvisitor;
import actypes;
import autocomplete;

struct CacheEntry
{
	ACSymbol[] symbols;
	SysTime modificationTime;
}

/**
 * Caches pre-parsed module information.
 */
struct ModuleCache
{
	@disable this();

	/**
	 * Clears the completion cache
	 */
	static void clear()
	{
		cache.clear();
	}

	/**
	 * Adds the given path to the list of directories checked for imports
	 */
	static void addImportPath(string path)
	{
		if (!exists(path) || importPaths.canFind(path))
			return;
		importPaths ~= path;
		foreach (fileName; dirEntries(path, "*.{d,di}", SpanMode.depth))
		{
			writeln("Loading and caching completions for ", fileName);
			getSymbolsInModule(fileName);
		}
	}

	/**
	 * Params:
	 *     moduleName = the name of the module in "a/b.d" form
	 * Returns:
	 *     The symbols defined in the given module
	 */
	static ACSymbol[] getSymbolsInModule(string moduleName)
	{
		writeln("Getting symbols for module ", moduleName);
		string location = resolveImportLoctation(moduleName);
		if (location is null)
			return [];
		if (!needsReparsing(location))
			return cache[location].symbols;

		auto visitor = new AutocompleteVisitor;
		try
		{
			File f = File(location);
			ubyte[] source = uninitializedArray!(ubyte[])(f.size);
			f.rawRead(source);

			LexerConfig config;
			auto tokens = source.byToken(config).array();
			Module mod = parseModule(tokens, location, &doesNothing);

			visitor.visit(mod);
			visitor.scope_.resolveSymbolTypes();
		}
		catch (Exception ex)
		{
			writeln("Couln't parse ", location, " due to exception: ", ex.msg);
			return [];
		}
		SysTime access;
		SysTime modification;
		getTimes(location, access, modification);
		if (location !in cache)
			cache[location] = CacheEntry.init;
		cache[location].modificationTime = modification;
		cache[location].symbols = visitor.symbols;
		return cache[location].symbols;
	}

	/**
	 * Params:
	 *     moduleName the name of the module being imported, in "a/b/c.d" style
	 * Returns:
	 *     The absolute path to the file that contains the module, or null if
	 *     not found.
	 */
	static string resolveImportLoctation(string moduleName)
	{
//		writeln("Resolving location of ", moduleName);
		if (isRooted(moduleName))
			return moduleName;

		foreach (path; importPaths)
		{
			string filePath = path ~ "/" ~ moduleName;
			if (filePath.exists())
				return filePath;
			filePath ~= "i"; // check for x.di if x.d isn't found
			if (filePath.exists())
				return filePath;
		}
		writeln("Could not find ", moduleName);
		return null;
	}

	static const(string[]) getImportPaths()
	{
		return cast(const(string[])) importPaths;
	}

private:

	/**
	 * Params:
	 *     mod = the path to the module
	 * Returns:
	 *     true  if the module needs to be reparsed, false otherwise
	 */
	static bool needsReparsing(string mod)
	{
		if (!exists(mod) || mod !in cache)
			return true;
		SysTime access;
		SysTime modification;
		getTimes(mod, access, modification);
		return cache[mod].modificationTime != modification;
	}

	// Mapping of file paths to their cached symbols.
	static CacheEntry[string] cache;

	// Listing of paths to check for imports
	static string[] importPaths;
}
