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

module dsymbol.symbol;

import std.algorithm;
import std.array;
import std.container;
import std.typecons;
import std.allocator;

import containers.ttree;
import containers.unrolledlist;
import containers.slist;
import std.d.lexer;

import dsymbol.builtin.names;
import dsymbol.string_interning;
public import dsymbol.string_interning : istring;

import std.range : isOutputRange;

/**
 * Identifies the kind of the item in an identifier completion list
 */
enum CompletionKind : char
{
	/// Invalid completion kind. This is used internally and will never
	/// be returned in a completion response.
	dummy = '?',

	/// Import symbol. This is used internally and will never
	/// be returned in a completion response.
	importSymbol = '*',

	/// With symbol. This is used internally and will never
	/// be returned in a completion response.
	withSymbol = 'w',

	/// class names
	className = 'c',

	/// interface names
	interfaceName = 'i',

	/// structure names
	structName = 's',

	/// union name
	unionName = 'u',

	/// variable name
	variableName = 'v',

	/// member variable
	memberVariableName = 'm',

	/// keyword, built-in version, scope statement
	keyword = 'k',

	/// function or method
	functionName = 'f',

	/// enum name
	enumName = 'g',

	/// enum member
	enumMember = 'e',

	/// package name
	packageName = 'P',

	/// module name
	moduleName = 'M',

	/// array
	array = 'a',

	/// associative array
	assocArray = 'A',

	/// alias name
	aliasName = 'l',

	/// template name
	templateName = 't',

	/// mixin template name
	mixinTemplateName = 'T'
}


/**
 * Any special information about a variable declaration symbol.
 */
enum SymbolQualifier : ubyte
{
	/// _none
	none,
	/// the symbol is an array
	array,
	/// the symbol is a associative array
	assocArray,
	/// the symbol is a function or delegate pointer
	func
}

/**
 * Autocompletion symbol
 */
struct DSymbol
{
public:

	/**
	 * Copying is disabled.
	 */
	@disable this();

	/// ditto
	@disable this(this);

	/**
	 * Params:
	 *     name = the symbol's name
	 */
	this(string name) nothrow @safe
	{
		this.name = name is null ? istring(null) : internString(name);
	}

	/// ditto
	this(istring name) nothrow @safe
	{
		this.name = name;
	}

	/**
	 * Params:
	 *     name = the symbol's name
	 *     kind = the symbol's completion kind
	 */
	this(string name, CompletionKind kind) nothrow @safe @nogc
	{
		this.name = name is null ? istring(name) : internString(name);
		this.kind = kind;
	}

	/// ditto
	this(istring name, CompletionKind kind) nothrow @safe @nogc
	{
		this.name = name;
		this.kind = kind;
	}

	/**
	 * Params:
	 *     name = the symbol's name
	 *     kind = the symbol's completion kind
	 *     resolvedType = the resolved type of the symbol
	 */
	this(string name, CompletionKind kind, DSymbol* type)
	{
		this.name = name is null ? istring(name) : internString(name);
		this.kind = kind;
		this.type = type;
	}

	/// ditto
	this(istring name, CompletionKind kind, DSymbol* type)
	{
		this.name = name;
		this.kind = kind;
		this.type = type;
	}

	int opCmp(ref const DSymbol other) const pure nothrow @safe
	{
		// Compare the pointers because the strings have been interned.
		// Identical strings MUST have the same address
		int r = name.ptr > other.name.ptr;
		if (name.ptr < other.name.ptr)
			r = -1;
		return r;
	}

	bool opEquals(ref const DSymbol other) const pure nothrow @safe
	{
		return other.name.ptr == this.name.ptr;
	}

	size_t toHash() const pure nothrow @safe
	{
		return (cast(size_t) name.ptr) * 27_644_437;
	}

	/**
	 * Gets all parts whose name matches the given string.
	 */
	DSymbol*[] getPartsByName(istring name) const
	{
		import std.range : chain;
		DSymbol s = DSymbol(name);
		DSymbol p = DSymbol(IMPORT_SYMBOL_NAME);
		auto app = appender!(DSymbol*[])();
		foreach (part; parts.equalRange(&s))
			app.put(part);
		foreach (im; parts.equalRange(&p))
			app.put(im.type.getPartsByName(name));
		return app.data();
	}

	/**
	 * Adds all parts and parts of parts with the given name to the given output
	 * range.
	 */
	void getAllPartsNamed(OR)(string name, ref OR outputRange) const
		if (isOutputRange!(OR, DSymbol*))
	{
		foreach (part; parts[])
		{
			if (part.name == name)
				outputRange.put(part);
			part.getAllPartsNamed(name, outputRange);
		}
	}

	/**
	 * DSymbol's name
	 */
	istring name;

	/**
	 * Symbols that compose this symbol, such as enum members, class variables,
	 * methods, etc.
	 */
	TTree!(DSymbol*, true, "a < b", false) parts;

	/**
	 * Calltip to display if this is a function
	 */
	istring callTip;

	/**
	 * Module containing the symbol.
	 */
	istring symbolFile;

	/**
	 * Documentation for the symbol.
	 */
	istring doc;

	/**
	 * The symbol that represents the type.
	 */
	DSymbol* type;

	/**
	 * DSymbol location
	 */
	size_t location;

	/**
	 * The kind of symbol
	 */
	CompletionKind kind;

	/**
	 * DSymbol qualifier
	 */
	SymbolQualifier qualifier;
}
