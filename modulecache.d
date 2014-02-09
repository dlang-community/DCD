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

module modulecache;

import std.file;
import std.datetime;
import stdx.lexer;
import stdx.d.lexer;
import stdx.d.parser;
import stdx.d.ast;
import std.stdio;
import std.array;
import std.path;
import std.algorithm;
import std.conv;
import std.container;

import actypes;
import semantic;
import astconverter;
import stupidlog;

bool cacheComparitor(CacheEntry* a, CacheEntry* b) pure nothrow
{
	return cast(ubyte[]) a.path < cast(ubyte[]) b.path;
}

private struct CacheEntry
{
	ACSymbol*[] symbols;
	SysTime modificationTime;
	string path;
	void opAssign(ref const CacheEntry other)
	{
		this.symbols = cast(typeof(symbols)) other.symbols;
		this.modificationTime = other.modificationTime;
	}
}

bool existanceCheck(A)(A path)
{
	if (path.exists())
		return true;
	Log.error("Cannot cache modules in ", path, " because it does not exist");
	return false;
}

static this()
{
	ModuleCache.cache = new RedBlackTree!(CacheEntry*, cacheComparitor);
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
	static void addImportPaths(string[] paths)
	{
		string[] addedPaths = paths.filter!(a => existanceCheck(a)).array();
		importPaths ~= addedPaths;
		foreach (path; addedPaths)
		{
			foreach (fileName; dirEntries(path, "*.{d,di}", SpanMode.depth))
			{
				getSymbolsInModule(fileName);
			}
		}
	}

	/**
	 * Params:
	 *     moduleName = the name of the module in "a/b/c" form
	 * Returns:
	 *     The symbols defined in the given module
	 */
	static ACSymbol*[] getSymbolsInModule(string location)
	{
		if (location is null)
			return [];

		if (!needsReparsing(location))
		{
			CacheEntry e;
			e.path = location;
			auto r = cache.equalRange(&e);
			if (!r.empty)
				return r.front.symbols;
			return [];
		}

		Log.info("Getting symbols for ", location);

		recursionGuard[location] = true;

		ACSymbol*[] symbols;
		try
		{
			import core.memory;
			File f = File(location);
			ubyte[] source = uninitializedArray!(ubyte[])(cast(size_t)f.size);
			f.rawRead(source);

			GC.disable();
			LexerConfig config;
			config.fileName = location;
			StringCache* cache = new StringCache(StringCache.defaultBucketCount);
			auto tokens = source.byToken(config, cache).array();
			symbols = convertAstToSymbols(tokens, location);
			GC.enable();
		}
		catch (Exception ex)
		{
			Log.error("Couln't parse ", location, " due to exception: ", ex.msg);
			return [];
		}
		SysTime access;
		SysTime modification;
		getTimes(location, access, modification);
		CacheEntry* c = new CacheEntry(symbols, modification, location);
		cache.insert(c);
		recursionGuard[location] = false;
		return symbols;
	}

	/**
	 * Params:
	 *     moduleName the name of the module being imported, in "a/b/c" style
	 * Returns:
	 *     The absolute path to the file that contains the module, or null if
	 *     not found.
	 */
	static string resolveImportLoctation(string moduleName)
	{
		if (isRooted(moduleName))
			return moduleName;
		string[] alternatives;
		foreach (path; importPaths)
		{
			string filePath = buildPath(path, moduleName);
			if (exists(filePath ~ ".d") && isFile(filePath ~ ".d"))
				alternatives = (filePath ~ ".d") ~ alternatives;
			else if (exists(filePath ~ ".di") && isFile(filePath ~ ".di"))
				alternatives = (filePath ~ ".di") ~ alternatives;
			else if (exists(filePath) && isDir(filePath))
			{
				string packagePath = buildPath(filePath, "package.d");
				if (exists(packagePath) && isFile(packagePath))
				{
					alternatives ~= packagePath;
					continue;
				}
				packagePath ~= "i";
				if (exists(packagePath) && isFile(packagePath))
					alternatives ~= packagePath;
			}
		}
		return alternatives.length > 0 ? alternatives[0] : null;
	}

	static const(string[]) getImportPaths()
	{
		return cast(const(string[])) importPaths;
	}

	static this()
	{
		stringCache = new StringCache(StringCache.defaultBucketCount);
	}

	static StringCache* stringCache;

private:

	/**
	 * Params:
	 *     mod = the path to the module
	 * Returns:
	 *     true  if the module needs to be reparsed, false otherwise
	 */
	static bool needsReparsing(string mod)
	{
		if (mod !in recursionGuard)
			return true;
		if (recursionGuard[mod])
			return false;
		if (!exists(mod))
			return true;
		CacheEntry e;
		e.path = mod;
		auto r = cache.equalRange(&e);
		if (r.empty)
			return true;
		SysTime access;
		SysTime modification;
		getTimes(mod, access, modification);
		return r.front.modificationTime != modification;
	}

	// Mapping of file paths to their cached symbols.
	static RedBlackTree!(CacheEntry*, cacheComparitor) cache;

	static bool[string] recursionGuard;

	// Listing of paths to check for imports
	static string[] importPaths;
}
