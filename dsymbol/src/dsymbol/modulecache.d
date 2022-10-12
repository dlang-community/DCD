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

module dsymbol.modulecache;

import containers.dynamicarray;
import containers.hashset;
import containers.ttree;
import containers.unrolledlist;
import dsymbol.conversion;
import dsymbol.conversion.first;
import dsymbol.conversion.second;
import dsymbol.cache_entry;
import dsymbol.scope_;
import dsymbol.semantic;
import dsymbol.symbol;
import dsymbol.string_interning;
import dsymbol.deferred;
import std.algorithm;
import std.experimental.allocator;
import std.experimental.allocator.building_blocks.allocator_list;
import std.experimental.allocator.building_blocks.region;
import std.experimental.allocator.building_blocks.null_allocator;
import std.experimental.allocator.mallocator : Mallocator;
import std.experimental.allocator.gc_allocator : GCAllocator;
import std.conv;
import dparse.ast;
import std.datetime;
import dparse.lexer;
import dparse.parser;
import std.experimental.logger;
import std.file;
import std.experimental.lexer;
import std.path;

/**
 * Returns: true if a file exists at the given path.
 */
bool existanceCheck(A)(A path)
{
	if (path.exists())
		return true;
	warning("Cannot cache modules in ", path, " because it does not exist");
	return false;
}

alias DeferredSymbolsAllocator = GCAllocator; // NOTE using `Mallocator` here fails when analysing Phobos as `free(): invalid pointer`

/**
 * Caches pre-parsed module information.
 */
struct ModuleCache
{
	/// No copying.
	@disable this(this);

	~this()
	{
		clear();
	}

	/**
	 * Adds the given paths to the list of directories checked for imports.
	 * Performs duplicate checking, so multiple instances of the same path will
	 * not be present.
	 */
	void addImportPaths(const string[] paths)
	{
		import std.path : baseName;
		import std.array : array;

		auto newPaths = paths
			.map!(a => absolutePath(expandTilde(a)))
			.filter!(a => existanceCheck(a) && !importPaths[].canFind!(b => b.path == a))
			.map!(a => ImportPath(istring(a)))
			.array;
		importPaths.insert(newPaths);
	}

	/**
	 * Removes the given paths from the list of directories checked for
	 * imports. Corresponding cache entries are removed.
	 */
	void removeImportPaths(const string[] paths)
	{
		import std.array : array;

		foreach (path; paths[])
		{
			if (!importPaths[].canFind!(a => a.path == path))
			{
				warning("Cannot remove ", path, " because it is not imported");
				continue;
			}

			foreach (ref importPath; importPaths[].filter!(a => a.path == path).array)
				importPaths.remove(importPath);

			foreach (cacheEntry; cache[])
			{
				if (cacheEntry.path.data.startsWith(path))
				{
					foreach (deferredSymbol; deferredSymbols[].find!(d => d.symbol.symbolFile.data.startsWith(cacheEntry.path.data)))
					{
						deferredSymbols.remove(deferredSymbol);
						DeferredSymbolsAllocator.instance.dispose(deferredSymbol);
					}

					cache.remove(cacheEntry);
					CacheAllocator.instance.dispose(cacheEntry);
				}
			}
		}
	}

	/**
	 * Clears the cache from all import paths
	 */
	void clear()
	{
		foreach (entry; cache[])
			CacheAllocator.instance.dispose(entry);
		foreach (symbol; deferredSymbols[])
			DeferredSymbolsAllocator.instance.dispose(symbol);

		cache.clear();
		deferredSymbols.clear();
		importPaths.clear();
	}

	/**
	 * Caches the module at the given location
	 */
	DSymbol* cacheModule(string location)
	{
		import std.stdio : File;

		assert (location !is null);

		const cachedLocation = istring(location);

		if (recursionGuard.contains(&cachedLocation.data[0]))
			return null;

		if (!needsReparsing(cachedLocation))
			return getEntryFor(cachedLocation).symbol;

		recursionGuard.insert(&cachedLocation.data[0]);

		File f = File(cachedLocation);
		immutable fileSize = cast(size_t) f.size;
		if (fileSize == 0)
			return null;

		const(Token)[] tokens;
		auto parseStringCache = StringCache(fileSize.optimalBucketCount);
		{
			ubyte[] source = cast(ubyte[]) Mallocator.instance.allocate(fileSize);
			scope (exit) Mallocator.instance.deallocate(source);
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

		CacheEntry* newEntry = CacheAllocator.instance.make!CacheEntry();

		import dparse.rollback_allocator:RollbackAllocator;
		RollbackAllocator parseAllocator;
		Module m = parseModuleSimple(tokens[], cachedLocation, &parseAllocator);

		scope first = new FirstPass(m, cachedLocation, &this, newEntry);
		first.run();

		secondPass(first.rootSymbol, first.moduleScope, this);

		typeid(Scope).destroy(first.moduleScope);
		symbolsAllocated += first.symbolsAllocated;

		SysTime access;
		SysTime modification;
		getTimes(cachedLocation.data, access, modification);

		newEntry.symbol = first.rootSymbol.acSymbol;
		newEntry.modificationTime = modification;
		newEntry.path = cachedLocation;

		CacheEntry* oldEntry = getEntryFor(cachedLocation);
		if (oldEntry !is null)
		{
			// Generate update mapping from the old symbol to the new one
			UpdatePairCollection updatePairs;
			generateUpdatePairs(oldEntry.symbol, newEntry.symbol, updatePairs);

			// Apply updates to all symbols in modules that depend on this one
			cache[].filter!(a => a.dependencies.contains(cachedLocation)).each!(
				upstream => upstream.symbol.updateTypes(updatePairs));

			// Remove the old symbol.
			cache.remove(oldEntry, entry => CacheAllocator.instance.dispose(entry));
		}

		cache.insert(newEntry);
		recursionGuard.remove(&cachedLocation.data[0]);

		resolveDeferredTypes(cachedLocation);

		typeid(SemanticSymbol).destroy(first.rootSymbol);

		return newEntry.symbol;
	}

	/**
	 * Resolves types for deferred symbols
	 */
	void resolveDeferredTypes(istring location)
	{
		DeferredSymbols temp;
		temp.insert(deferredSymbols[]);
		deferredSymbols.clear();
		foreach (deferred; temp[])
		{
			if (!deferred.imports.empty && !deferred.dependsOn(location))
			{
				deferredSymbols.insert(deferred);
				continue;
			}
			assert(deferred.symbol.type is null);
			if (deferred.symbol.kind == CompletionKind.importSymbol)
			{
				resolveImport(deferred.symbol, deferred.typeLookups, this);
			}
			else if (!deferred.typeLookups.empty)
			{
				// TODO: Is .front the right thing to do here?
				resolveTypeFromType(deferred.symbol, deferred.typeLookups.front, null,
					this, &deferred.imports);
			}
			DeferredSymbolsAllocator.instance.dispose(deferred);
		}
	}

	/**
	 * Params:
	 *     moduleName = the name of the module in "a/b/c" form
	 * Returns:
	 *     The symbols defined in the given module, or null if the module is
	 *     not cached yet.
	 */
	DSymbol* getModuleSymbol(istring location)
	{
		auto existing = getEntryFor(location);
		return existing ? existing.symbol : cacheModule(location);
	}

	/**
	 * Params:
	 *     moduleName = the name of the module being imported, in "a/b/c" style
	 * Returns:
	 *     The absolute path to the file that contains the module, or null if
	 *     not found.
	 */
	istring resolveImportLocation(string moduleName)
	{
		assert(moduleName !is null, "module name is null");
		if (isRooted(moduleName))
			return istring(moduleName);
		string alternative;
		foreach (importPath; importPaths[])
		{
			auto path = importPath.path;
			// import path is a filename
			// first check string if this is a feasable path (no filesystem usage)
			if (path.stripExtension.endsWith(moduleName)
				&& path.existsAnd!isFile)
			{
				// prefer exact import names above .di/package.d files
				return istring(path);
			}
			// no exact matches and no .di/package.d matches either
			else if (!alternative.length)
			{
				string dotDi = buildPath(path, moduleName) ~ ".di";
				string dotD = dotDi[0 .. $ - 1];
				string withoutSuffix = dotDi[0 .. $ - 3];
				if (existsAnd!isFile(dotD))
					return istring(dotD); // return early for exactly matching .d files
				else if (existsAnd!isFile(dotDi))
					alternative = dotDi;
				else if (existsAnd!isDir(withoutSuffix))
				{
					string packagePath = buildPath(withoutSuffix, "package.di");
					if (existsAnd!isFile(packagePath[0 .. $ - 1]))
						alternative = packagePath[0 .. $ - 1];
					else if (existsAnd!isFile(packagePath))
						alternative = packagePath;
				}
			}
			// we have a potential .di/package.d file but continue searching for
			// exact .d file matches to use instead
			else
			{
				string dotD = buildPath(path, moduleName) ~ ".d";
				if (existsAnd!isFile(dotD))
					return istring(dotD); // return early for exactly matching .d files
			}
		}
		return alternative.length > 0 ? istring(alternative) : istring(null);
	}

	auto getImportPaths() const
	{
		return importPaths[].map!(a => a.path);
	}

	auto getAllSymbols()
	{
		scanAll();
		return cache[];
	}

	alias DeferredSymbols = UnrolledList!(DeferredSymbol*, DeferredSymbolsAllocator);
	DeferredSymbols deferredSymbols;

	/// Count of autocomplete symbols that have been allocated
	uint symbolsAllocated;

private:

	CacheEntry* getEntryFor(istring cachedLocation)
	{
		CacheEntry dummy;
		dummy.path = cachedLocation;
		auto r = cache.equalRange(&dummy);
		return r.empty ? null : r.front;
	}

	/**
	 * Params:
	 *     mod = the path to the module
	 * Returns:
	 *     true  if the module needs to be reparsed, false otherwise
	 */
	bool needsReparsing(istring mod)
	{
		if (!exists(mod.data))
			return true;
		CacheEntry e;
		e.path = mod;
		auto r = cache.equalRange(&e);
		if (r.empty)
			return true;
		SysTime access;
		SysTime modification;
		getTimes(mod.data, access, modification);
		return r.front.modificationTime != modification;
	}

	void scanAll()
	{
		foreach (ref importPath; importPaths)
		{
			if (importPath.scanned)
				continue;
			scope(success) importPath.scanned = true;

			if (importPath.path.existsAnd!isFile)
			{
				if (importPath.path.baseName.startsWith(".#"))
					continue;
				cacheModule(importPath.path);
			}
			else
			{
				void scanFrom(const string root)
				{
					if (exists(buildPath(root, ".no-dcd")))
						return;

					try foreach (f; dirEntries(root, SpanMode.shallow))
					{
						if (f.name.existsAnd!isFile)
						{
							if (!f.name.extension.among(".d", ".di") || f.name.baseName.startsWith(".#"))
								continue;
							cacheModule(f.name);
						}
						else scanFrom(f.name);
					}
					catch(FileException) {}
				}
				scanFrom(importPath.path);
			}
		}
	}

	// Mapping of file paths to their cached symbols.
	alias CacheAllocator = GCAllocator; // NOTE using `Mallocator` here fails when analysing Phobos as `Segmentation fault (core dumped)`
	alias Cache = TTree!(CacheEntry*, CacheAllocator);
	Cache cache;

	HashSet!(immutable(char)*) recursionGuard;

	struct ImportPath
	{
		string path;
		bool scanned;
	}

	// Listing of paths to check for imports
	UnrolledList!ImportPath importPaths;
}

/// Wrapper to check some attribute of a path, ignoring errors
/// (such as on a broken symlink).
private static bool existsAnd(alias fun)(string file)
{
	try
		return fun(file);
	catch (FileException e)
		return false;
}

/// same as getAttributes without throwing
/// Returns: true if exists, false otherwise
private static bool getFileAttributesFast(R)(R name, uint* attributes)
{
	version (Windows)
	{
		import std.internal.cstring : tempCStringW;
		import core.sys.windows.winnt : INVALID_FILE_ATTRIBUTES;
		import core.sys.windows.winbase : GetFileAttributesW;

		auto namez = tempCStringW(name);
		static auto trustedGetFileAttributesW(const(wchar)* namez) @trusted
		{
			return GetFileAttributesW(namez);
		}
		*attributes = trustedGetFileAttributesW(namez);
		return *attributes != INVALID_FILE_ATTRIBUTES;
	}
	else version (Posix)
	{
		import core.sys.posix.sys.stat : stat, stat_t;
		import std.internal.cstring : tempCString;

		auto namez = tempCString(name);
		static auto trustedStat(const(char)* namez, out stat_t statbuf) @trusted
		{
			return stat(namez, &statbuf);
		}

		stat_t statbuf;
		const ret = trustedStat(namez, statbuf) == 0;
		*attributes = statbuf.st_mode;
		return ret;
	}
	else
	{
		static assert(false, "Unimplemented getAttributes check");
	}
}

private static bool existsAnd(alias fun : isFile)(string file)
{
	uint attributes;
	if (!getFileAttributesFast(file, &attributes))
		return false;
	return attrIsFile(attributes);
}

private static bool existsAnd(alias fun : isDir)(string file)
{
	uint attributes;
	if (!getFileAttributesFast(file, &attributes))
		return false;
	return attrIsDir(attributes);
}

version (Windows)
{
	unittest
	{
		assert(existsAnd!isFile(`C:\Windows\regedit.exe`));
		assert(existsAnd!isDir(`C:\Windows`));
		assert(!existsAnd!isDir(`C:\Windows\regedit.exe`));
		assert(!existsAnd!isDir(`C:\SomewhereNonExistant\nonexistant.exe`));
		assert(!existsAnd!isFile(`C:\SomewhereNonExistant\nonexistant.exe`));
		assert(!existsAnd!isFile(`C:\Windows`));
	}
}
else version (Posix)
{
	unittest
	{
		assert(existsAnd!isFile(`/bin/sh`));
		assert(existsAnd!isDir(`/bin`));
		assert(!existsAnd!isDir(`/bin/sh`));
		assert(!existsAnd!isDir(`/nonexistant_dir/__nonexistant`));
		assert(!existsAnd!isFile(`/nonexistant_dir/__nonexistant`));
		assert(!existsAnd!isFile(`/bin`));
	}
}
