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

module dsymbol.string_interning;

import std.traits : Unqual;
import dparse.lexer;

/// Obsolete, use `istring` constructor instead
istring internString(string s) nothrow @nogc @safe
{
	return istring(s);
}

static this()
{
	stringCache = StringCache(StringCache.defaultBucketCount);
}

static ~this()
{
	destroy(stringCache);
}

private StringCache stringCache = void;

struct istring
{
nothrow @nogc @safe:
	/// Interns the given string and returns the interned version. Handles empty strings too.
	this(string s)
	{
		if (s.length > 0)
			_data = stringCache.intern(s);
	}

pure:
	void opAssign(T)(T other) if (is(Unqual!T == istring))
	{
		_data = other._data;
	}

	bool opCast(To : bool)() const
	{
		return _data.length > 0;
	}

	ptrdiff_t opCmpFast(const istring another) const @trusted
	{
		// Interned strings can be compared by the pointers.
		// Identical strings MUST have the same address
		return (cast(ptrdiff_t) _data.ptr) - (cast(ptrdiff_t) another._data.ptr);
	}
	ptrdiff_t opCmp(const string another) const
	{
		import std.algorithm.comparison : cmp;
		// Compare as usual, because another string may come from somewhere else
		return cmp(_data, another);
	}

	bool opEquals(const istring another) const @trusted
	{
		return _data.ptr is another._data.ptr;
	}
	bool opEquals(const string another) const
	{
		return _data == another;
	}

	size_t toHash() const @trusted
	{
		return (cast(size_t) _data.ptr) * 27_644_437;
	}

	string data() const
	{
		return _data;
	}

	alias data this;
	private string _data;
}
