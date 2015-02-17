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
import containers.ttree;
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
	ACSymbol* symbol;
	SysTime modificationTime;
	string path;

	int opCmp(ref const CacheEntry other) const
	{
		int r = path > other.path;
		if (path < other.path)
			return -1;
		return r;
	}

	bool opEquals(ref const CacheEntry other) const
	{
		return path == other.path;
	}

	size_t toHash() const nothrow @safe
	{
		import core.internal.hash : hashOf;
		return hashOf(path);
	}

	void opAssign(ref const CacheEntry other)
	{
		assert(false);
	}
}

/**
 * Returns: true if a file exists at the given path.
 */
bool existanceCheck(A)(A path)
{
	if (path.exists())
		return true;
	Log.error("Cannot cache modules in ", path, " because it does not exist");
	return false;
}

static this()
{
	ModuleCache.symbolAllocator = new CAllocatorImpl!(BlockAllocator!(1024 * 16));
}

/**
 * Caches pre-parsed module information.
 */
struct ModuleCache
{
	/// No copying.
	@disable this();

	/**
	 * Adds the given path to the list of directories checked for imports.
	 * Performs duplicate checking, so multiple instances of the same path will
	 * not be present.
	 */
	static void addImportPaths(string[] paths)
	{
		import string_interning : internString;
		import std.array : array;
		auto newPaths = paths.filter!(a => existanceCheck(a) && !importPaths[].canFind(a)).map!(internString).array;
		importPaths.insert(newPaths);

		foreach (path; newPaths[])
		{
			foreach (fileName; dirEntries(path, "*.{d,di}", SpanMode.depth))
			{
				import std.path: baseName;
				if(fileName.baseName.startsWith(".#")) continue;
				getModuleSymbol(fileName);
			}
		}
	}

	/// TODO: Implement
	static void clear()
	{
		Log.info("ModuleCache.clear is not yet implemented.");
	}

	/**
	 * Params:
	 *     moduleName = the name of the module in "a/b/c" form
	 * Returns:
	 *     The symbols defined in the given module
	 */
	static ACSymbol* getModuleSymbol(string location)
	{
		import string_interning : internString;
		import std.stdio : File;
		import std.typecons : scoped;

		assert (location !is null);

		istring cachedLocation = internString(location);

		if (!needsReparsing(cachedLocation))
		{
			CacheEntry e;
			e.path = cachedLocation;
			auto r = cache.equalRange(&e);
			if (!r.empty)
				return r.front.symbol;
			return null;
		}

		recursionGuard.insert(cachedLocation);

		ACSymbol* symbol;
		File f = File(cachedLocation);
		immutable fileSize = cast(size_t) f.size;
		if (fileSize == 0)
			return null;

		const(Token)[] tokens;
		auto parseStringCache = StringCache(StringCache.defaultBucketCount);
		{
			ubyte[] source = cast(ubyte[]) Mallocator.it.allocate(fileSize);
			scope (exit) Mallocator.it.deallocate(source);
			f.rawRead(source);
			LexerConfig config;
			config.fileName = cachedLocation;

			// The first three bytes are sliced off here if the file starts with a
			// Unicode byte order mark. The lexer/parser don't handle them.
			tokens = getTokensForParser(
				(source.length >= 3 && source[0 .. 3] == "\xef\xbb\xbf"c)
				? source[3 .. $] : source,
				config, &parseStringCache);
		}

		auto semanticAllocator = scoped!(CAllocatorImpl!(BlockAllocator!(1024 * 64)));
		Module m = parseModuleSimple(tokens[], cachedLocation, semanticAllocator);

		assert (symbolAllocator);
		auto first = scoped!FirstPass(m, cachedLocation, symbolAllocator,
			semanticAllocator);
		first.run();

		SecondPass second = SecondPass(first);
		second.run();

		ThirdPass third = ThirdPass(second);
		third.run();

		symbol = third.rootSymbol.acSymbol;

		typeid(Scope).destroy(third.moduleScope);
		symbolsAllocated += first.symbolsAllocated;

		SysTime access;
		SysTime modification;
		getTimes(cachedLocation, access, modification);

		CacheEntry e;
		e.path = cachedLocation;
		auto r = cache.equalRange(&e);
		CacheEntry* c = r.empty ? allocate!CacheEntry(Mallocator.it)
			: r.front;
		c.symbol = symbol;
		c.modificationTime = modification;
		c.path = cachedLocation;
		if (r.empty)
			cache.insert(c);
		recursionGuard.remove(cachedLocation);
		return symbol;
	}

	/**
	 * Params:
	 *     moduleName = the name of the module being imported, in "a/b/c" style
	 * Returns:
	 *     The absolute path to the file that contains the module, or null if
	 *     not found.
	 */
	static string resolveImportLoctation(string moduleName)
	{
		if (isRooted(moduleName))
			return moduleName;
		string[] alternatives;
		foreach (path; importPaths[])
		{
			string dotDi = buildPath(path, moduleName) ~ ".di";
			string dotD = dotDi[0 .. $ - 1];
			string withoutSuffix = dotDi[0 .. $ - 3];
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

	static auto getAllSymbols()
	{
		return cache[];
	}

	/// Count of autocomplete symbols that have been allocated
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
	static TTree!(CacheEntry*) cache;

	static HashSet!string recursionGuard;

	// Listing of paths to check for imports
	static UnrolledList!string importPaths;

	static CAllocator symbolAllocator;
}
