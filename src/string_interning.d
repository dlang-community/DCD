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

module string_interning;

import std.d.lexer;

/**
 * Interns the given string and returns the interned version.
 */
istring internString(string s) nothrow @safe @nogc
{
	return istring(stringCache.intern(s));
}

static this()
{
	stringCache = StringCache(StringCache.defaultBucketCount);
}

alias istring = InternedString;

//private size_t[string] dupCheck;
private StringCache stringCache = void;

private struct InternedString
{
    void opAssign(T)(T other) if (is(Unqual!T == istring))
    {
        this.data = other.data;
    }
	string data;
    alias data this;
private:
	import std.traits : Unqual;
}
