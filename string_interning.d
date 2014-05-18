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

import std.lexer;

string internString(string s)
{
//	import std.stdio;
//	import std.string;
//	size_t* p = s in dupCheck;
//	auto r = stringCache.intern(s);
	return stringCache.intern(s);
//	if (p !is null)
//		assert (*p == cast(size_t) r.ptr, format("%s, %016x, %016x", s, *p, r.ptr));
//	else
//		dupCheck[s] = cast(size_t) r.ptr;
//	stderr.writefln("%s\t%016x", r, r.ptr);
//	return r;
}

static this()
{
	stringCache = StringCache(StringCache.defaultBucketCount);
}

//private size_t[string] dupCheck;
private StringCache stringCache = void;
