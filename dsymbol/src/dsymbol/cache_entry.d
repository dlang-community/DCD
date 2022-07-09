module dsymbol.cache_entry;

import dsymbol.symbol;
import std.datetime;
import containers.openhashset;
import containers.unrolledlist;

/**
 * Module cache entry
 */
struct CacheEntry
{
	/// Module root symbol
	DSymbol* symbol;

	/// Modification time when this file was last cached
	SysTime modificationTime;

	/// The path to the module
	istring path;

	/// The modules that this module depends on
	OpenHashSet!istring dependencies;

	~this()
	{
		if (symbol !is null)
			typeid(DSymbol).destroy(symbol);
	}

pure nothrow @nogc @safe:

	ptrdiff_t opCmp(ref const CacheEntry other) const
	{
		return path.opCmpFast(other.path);
	}

	bool opEquals(ref const CacheEntry other) const
	{
		return path == other.path;
	}

	size_t toHash() const
	{
		return path.toHash();
	}

	@disable void opAssign(ref const CacheEntry other);
}
