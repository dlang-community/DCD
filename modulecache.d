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

import acvisitor;

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
	void clear()
	{
		cache = [];
	}

	/**
	 * Adds the given path to the list of directories checked for imports
	 */
	void addImportPath(string path)
	{
		importPaths ~= path;
	}

	/**
	 * Params:
	 *     moduleName = the name of the module in "a.b.c" form
	 * Returns:
	 *     The symbols defined in the given module
	 */
	ACSymbol[] getSymbolsInModule(string moduleName)
	{
		string location = resolveImportLoctation(moduleName);
		if (!needsReparsing(location))
			return;

		Module mod = parseModule(tokens, location, &doesNothing);
		auto visitor = new AutocompleteVisitor;
		visitor.visit(mod);
		cache[location].mod = visitor.symbols;
	}

	/**
	 * Params:
	 *     moduleName the name of the module being imported, in "a.b.c" style
	 * Returns:
	 *     The absolute path to the file that contains the module, or null if
	 *     not found.
	 */
	string resolveImportLoctation(string moduleName)
	{
		foreach (path; importPaths)
		{
			string filePath = path ~ "/" ~ imp;
			if (filePath.exists())
				return filePath;
			filePath ~= "i"; // check for x.di if x.d isn't found
			if (filePath.exists())
				return filePath;
		}
		return null;
	}

private:

	/**
	 * Params:
	 *     mod = the path to the module
	 * Returns:
	 *     true  if the module needs to be reparsed, false otherwise
	 */
    bool needsReparsing(string mod)
    {
        if (!exists(mod) || mod !in cache)
            return true;
        SysTime access;
        SysTime modification;
        getTimes(mod, access, modification);
        return cache[mod].modificationTime != modification;
    }

	// Mapping of file paths to their cached symbols.
    CacheEntry[string] cache;

	// Listing of paths to check for imports
	string[] importPaths;
}
