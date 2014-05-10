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

import std.algorithm;
import std.allocator;
import std.conv;
import std.d.ast;
import std.datetime;
import std.d.lexer;
import std.d.parser;
import std.file;
import std.lexer;
import std.path;

import actypes;
import semantic;
import memory.allocators;
import containers.karytree;
import containers.hashset;
import containers.unrolledlist;
import conversion.astconverter;
import conversion.first;
import conversion.second;
import conversion.third;
import containers.dynamicarray;
import stupidlog;
import messages;

private struct CacheEntry
{
	ACSymbol*[] symbols;
	SysTime modificationTime;
	string path;

	int opCmp(ref const CacheEntry other) const
	{
		if (path < other.path)
			return -1;
		if (path > other.path)
			return 1;
		return 0;
	}

	void opAssign(ref const CacheEntry other)
	{
		assert(false);
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
	ModuleCache.stringCache = new shared StringCache(StringCache.defaultBucketCount);
	ModuleCache.symbolAllocator = new CAllocatorImpl!(BlockAllocator!(1024 * 16));
}

/**
 * Caches pre-parsed module information.
 */
struct ModuleCache
{
	@disable this();

	static void clear()
	{
	}

	/**
	 * Adds the given path to the list of directories checked for imports
	 */
	static void addImportPaths(string[] paths)
	{
		import core.memory;
		foreach (path; paths.filter!(a => existanceCheck(a)))
			importPaths.insert(path);

		foreach (path; importPaths[])
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
		assert (location !is null);
		if (!needsReparsing(location))
		{
			CacheEntry e;
			e.path = location;
			auto r = cache.equalRange(&e);
			if (!r.empty)
				return r.front.symbols;
			return [];
		}

		string cachedLocation = stringCache.intern(location);

		Log.info("Getting symbols for ", cachedLocation);

		recursionGuard.insert(cachedLocation);



		ACSymbol*[] symbols;
//		try
//		{
			import core.memory;
			import std.stdio;
			import std.typecons;
			File f = File(cachedLocation);
			ubyte[] source = cast(ubyte[]) Mallocator.it.allocate(cast(size_t)f.size);
			f.rawRead(source);
			LexerConfig config;
			config.fileName = cachedLocation;
			shared parseStringCache = shared StringCache(StringCache.defaultBucketCount);
			auto semanticAllocator = scoped!(CAllocatorImpl!(BlockAllocator!(1024 * 64)));
			DynamicArray!(Token, false) tokens;
			auto tokenRange = byToken(
				(source.length >= 3 && source[0 .. 3] == "\xef\xbb\xbf"c) ? source[3 .. $] : source,
				config, &parseStringCache);
			foreach (t; tokenRange)
				tokens.insert(t);
			Mallocator.it.deallocate(source);

			Module m = parseModuleSimple(tokens[], cachedLocation, semanticAllocator);

			assert (symbolAllocator);
			auto first = scoped!FirstPass(m, cachedLocation, stringCache,
				symbolAllocator, semanticAllocator);
			first.run();

			SecondPass second = SecondPass(first);
			second.run();

			ThirdPass third = ThirdPass(second, cachedLocation);
			third.run();

			symbols = cast(ACSymbol*[]) Mallocator.it.allocate(
				third.rootSymbol.acSymbol.parts.length * (ACSymbol*).sizeof);
			size_t i = 0;
			foreach (part; third.rootSymbol.acSymbol.parts[])
				symbols[i++] = part;

			typeid(Scope).destroy(third.moduleScope);
			typeid(SemanticSymbol).destroy(third.rootSymbol);
			symbolsAllocated += first.symbolsAllocated;
//		}
//		catch (Exception ex)
//		{
//			Log.error("Couln't parse ", location, " due to exception: ", ex.msg);
//			return [];
//		}
		SysTime access;
		SysTime modification;
		getTimes(cachedLocation, access, modification);
		CacheEntry* c = allocate!CacheEntry(Mallocator.it, symbols,
			modification, cachedLocation);
		cache.insert(c);
		recursionGuard.remove(cachedLocation);
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
			string dotDi = buildPath(path, moduleName) ~ ".di";
			string dotD = dotDi[0 .. $ - 1];
			string withoutSuffix = dotDi[0 .. $ - 2];
			if (exists(dotD) && isFile(dotD))
				alternatives = (dotD) ~ alternatives;
			else if (exists(dotDi) && isFile(dotDi))
				alternatives ~= dotDi;
			else if (exists(withoutSuffix) && isDir(withoutSuffix))
			{
				string packagePath = buildPath(withoutSuffix, "package.di");
				if (exists(packagePath) && isFile(packagePath))
				{
					alternatives ~= packagePath;
					continue;
				}
				if (exists(packagePath[0 .. $ - 1]) && isFile(packagePath[0 .. $ - 1]))
					alternatives ~= packagePath[0 .. $ - 1];
			}
		}
		return alternatives.length > 0 ? alternatives[0] : null;
	}

	static auto getImportPaths()
	{
		return importPaths[];
	}

	static shared(StringCache)* stringCache;

	static uint symbolsAllocated;

private:

	/**
	 * Params:
	 *     mod = the path to the module
	 * Returns:
	 *     true  if the module needs to be reparsed, false otherwise
	 */
	static bool needsReparsing(string mod)
	{
		if (recursionGuard.contains(mod))
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
	static KAryTree!(CacheEntry*) cache;

	static HashSet!string recursionGuard;

	// Listing of paths to check for imports
	static UnrolledList!string importPaths;

	static CAllocator symbolAllocator;
}
