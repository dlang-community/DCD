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

module actypes;

import std.algorithm;
import std.array;
import std.container;
import std.typecons;
import std.allocator;

import containers.ttree;
import containers.unrolledlist;
import containers.slist;
import std.d.lexer;

import messages;
import string_interning;
public import string_interning : istring;

import std.range : isOutputRange;

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
struct ACSymbol
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
	this(string name, CompletionKind kind, ACSymbol* type)
	{
		this.name = name is null ? istring(name) : internString(name);
		this.kind = kind;
		this.type = type;
	}

	/// ditto
	this(istring name, CompletionKind kind, ACSymbol* type)
	{
		this.name = name;
		this.kind = kind;
		this.type = type;
	}

	int opCmp(ref const ACSymbol other) const pure nothrow @safe
	{
		// Compare the pointers because the strings have been interned.
		// Identical strings MUST have the same address
		int r = name.ptr > other.name.ptr;
		if (name.ptr < other.name.ptr)
			r = -1;
		return r;
	}

	bool opEquals(ref const ACSymbol other) const pure nothrow @safe
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
	ACSymbol*[] getPartsByName(istring name) const
	{
		import std.range : chain;
		ACSymbol s = ACSymbol(name);
		ACSymbol p = ACSymbol(IMPORT_SYMBOL_NAME);
		auto app = appender!(ACSymbol*[])();
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
		if (isOutputRange!(OR, ACSymbol*))
	{
		foreach (part; parts[])
		{
			if (part.name == name)
				outputRange.put(part);
			part.getAllPartsNamed(name, outputRange);
		}
	}

	/**
	 * Symbol's name
	 */
	istring name;

	/**
	 * Symbols that compose this symbol, such as enum members, class variables,
	 * methods, etc.
	 */
	TTree!(ACSymbol*, true, "a < b", false) parts;

	/**
	 * Calltip to display if this is a function
	 */
	string callTip;

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
	ACSymbol* type;

	/**
	 * Symbol location
	 */
	size_t location;

	/**
	 * The kind of symbol
	 */
	CompletionKind kind;

	/**
	 * Symbol qualifier
	 */
	SymbolQualifier qualifier;
}

/**
 * Contains symbols and supports lookup of symbols by cursor position.
 */
struct Scope
{
	/**
	 * Params:
	 *     begin = the beginning byte index
	 *     end = the ending byte index
	 */
	this (size_t begin, size_t end)
	{
		this.startLocation = begin;
		this.endLocation = end;
	}

	~this()
	{
		foreach (info; importInformation[])
			typeid(ImportInformation).destroy(info);
		foreach (child; children[])
			typeid(Scope).destroy(child);
	}

	/**
	 * Params:
	 *     cursorPosition = the cursor position in bytes
	 * Returns:
	 *     the innermost scope that contains the given cursor position
	 */
	Scope* getScopeByCursor(size_t cursorPosition) const
	{
		if (cursorPosition < startLocation) return null;
		if (cursorPosition > endLocation) return null;
		foreach (child; children[])
		{
			auto childScope = child.getScopeByCursor(cursorPosition);
			if (childScope !is null)
				return childScope;
		}
		return cast(typeof(return)) &this;
	}

	/**
	 * Params:
	 *     cursorPosition = the cursor position in bytes
	 * Returns:
	 *     all symbols in the scope containing the cursor position, as well as
	 *     the symbols in parent scopes of that scope.
	 */
	ACSymbol*[] getSymbolsInCursorScope(size_t cursorPosition) const
	{
		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		UnrolledList!(ACSymbol*) symbols;
		Scope* sc = s;
		while (sc !is null)
		{
			foreach (item; sc.symbols[])
			{
				if (item.type !is null && (item.kind == CompletionKind.importSymbol
					|| item.kind == CompletionKind.withSymbol))
				{
					foreach (i; item.type.parts[])
						symbols.insert(i);
				}
				else
					symbols.insert(item);
			}
			sc = sc.parent;
		}
		return array(symbols[]);
	}

	/**
	 * Params:
	 *     name = the symbol name to search for
	 * Returns:
	 *     all symbols in this scope or parent scopes with the given name
	 */
	ACSymbol*[] getSymbolsByName(istring name) const
	{
		ACSymbol s = ACSymbol(name);
		auto er = symbols.equalRange(&s);
		if (!er.empty)
			return array(er);

		// Check symbols from "with" statement
		ACSymbol ir2 = ACSymbol(WITH_SYMBOL_NAME);
		auto r2 = symbols.equalRange(&ir2);
		if (!r2.empty)
		{
			auto app = appender!(ACSymbol*[])();
			foreach (e; r2)
			{
				if (e.type is null)
					continue;
				foreach (withSymbol; e.type.parts.equalRange(&s))
					app.put(withSymbol);
			}
			if (app.data.length > 0)
				return app.data;
		}

		// Check imported symbols
		ACSymbol ir = ACSymbol(IMPORT_SYMBOL_NAME);
		auto r = symbols.equalRange(&ir);
		if (!r.empty)
		{
			auto app = appender!(ACSymbol*[])();
			foreach (e; r)
				foreach (importedSymbol; e.type.parts.equalRange(&s))
					app.put(importedSymbol);
			if (app.data.length > 0)
				return app.data;
		}
		if (parent is null)
			return [];
		return parent.getSymbolsByName(name);
	}

	/**
	 * Params:
	 *     name = the symbol name to search for
	 *     cursorPosition = the cursor position in bytes
	 * Returns:
	 *     all symbols with the given name in the scope containing the cursor
	 *     and its parent scopes
	 */
	ACSymbol*[] getSymbolsByNameAndCursor(istring name, size_t cursorPosition) const
	{
		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		return s.getSymbolsByName(name);
	}

	/**
	 * Returns an array of symbols that are present at global scope
	 */
	ACSymbol*[] getSymbolsAtGlobalScope(istring name) const
	{
		if (parent !is null)
			return parent.getSymbolsAtGlobalScope(name);
		return getSymbolsByName(name);
	}

	/// Imports contained in this scope
	UnrolledList!(ImportInformation*) importInformation;

	/// The scope that contains this one
	Scope* parent;

	/// Child scopes
	UnrolledList!(Scope*, false) children;

	/// Start location of this scope in bytes
	size_t startLocation;

	/// End location of this scope in bytes
	size_t endLocation;

	/// Symbols contained in this scope
	TTree!(ACSymbol*, true, "a < b", false) symbols;
}

/**
 * Import information
 */
struct ImportInformation
{
	/// Import statement parts
	UnrolledList!istring importParts;
	/// module relative path
	istring modulePath;
	/// symbols to import from this module
	UnrolledList!(Tuple!(istring, istring), false) importedSymbols;
	/// true if the import is public
	bool isPublic;
}


/**
 * Symbols for the built in types
 */
TTree!(ACSymbol*, true, "a < b", false) builtinSymbols;

/**
 * Array properties
 */
TTree!(ACSymbol*, true, "a < b", false) arraySymbols;

/**
 * Associative array properties
 */
TTree!(ACSymbol*, true, "a < b", false) assocArraySymbols;

/**
 * Struct, enum, union, class, and interface properties
 */
TTree!(ACSymbol*, true, "a < b", false) aggregateSymbols;

/**
 * Class properties
 */
TTree!(ACSymbol*, true, "a < b", false) classSymbols;

private immutable(istring[24]) builtinTypeNames;

/// Constants for buit-in or dummy symbol names
immutable istring IMPORT_SYMBOL_NAME;
/// ditto
immutable istring WITH_SYMBOL_NAME;
/// ditto
immutable istring CONSTRUCTOR_SYMBOL_NAME;
/// ditto
immutable istring DESTRUCTOR_SYMBOL_NAME;
/// ditto
immutable istring ARGPTR_SYMBOL_NAME;
/// ditto
immutable istring ARGUMENTS_SYMBOL_NAME;
/// ditto
immutable istring THIS_SYMBOL_NAME;
/// ditto
immutable istring UNITTEST_SYMBOL_NAME;
immutable istring DOUBLE_LITERAL_SYMBOL_NAME;
immutable istring FLOAT_LITERAL_SYMBOL_NAME;
immutable istring IDOUBLE_LITERAL_SYMBOL_NAME;
immutable istring IFLOAT_LITERAL_SYMBOL_NAME;
immutable istring INT_LITERAL_SYMBOL_NAME;
immutable istring LONG_LITERAL_SYMBOL_NAME;
immutable istring REAL_LITERAL_SYMBOL_NAME;
immutable istring IREAL_LITERAL_SYMBOL_NAME;
immutable istring UINT_LITERAL_SYMBOL_NAME;
immutable istring ULONG_LITERAL_SYMBOL_NAME;
immutable istring CHAR_LITERAL_SYMBOL_NAME;
immutable istring DSTRING_LITERAL_SYMBOL_NAME;
immutable istring STRING_LITERAL_SYMBOL_NAME;
immutable istring WSTRING_LITERAL_SYMBOL_NAME;

/**
 * Translates the IDs for built-in types into an interned string.
 */
istring getBuiltinTypeName(IdType id) nothrow pure @nogc @safe
{
	switch (id)
	{
	case tok!"int": return builtinTypeNames[0];
	case tok!"uint": return builtinTypeNames[1];
	case tok!"double": return builtinTypeNames[2];
	case tok!"idouble": return builtinTypeNames[3];
	case tok!"float": return builtinTypeNames[4];
	case tok!"ifloat": return builtinTypeNames[5];
	case tok!"short": return builtinTypeNames[6];
	case tok!"ushort": return builtinTypeNames[7];
	case tok!"long": return builtinTypeNames[8];
	case tok!"ulong": return builtinTypeNames[9];
	case tok!"char": return builtinTypeNames[10];
	case tok!"wchar": return builtinTypeNames[11];
	case tok!"dchar": return builtinTypeNames[12];
	case tok!"bool": return builtinTypeNames[13];
	case tok!"void": return builtinTypeNames[14];
	case tok!"cent": return builtinTypeNames[15];
	case tok!"ucent": return builtinTypeNames[16];
	case tok!"real": return builtinTypeNames[17];
	case tok!"ireal": return builtinTypeNames[18];
	case tok!"byte": return builtinTypeNames[19];
	case tok!"ubyte": return builtinTypeNames[20];
	case tok!"cdouble": return builtinTypeNames[21];
	case tok!"cfloat": return builtinTypeNames[22];
	case tok!"creal": return builtinTypeNames[23];
	default: assert (false);
	}
}


/**
 * Initializes builtin types and the various properties of builtin types
 */
static this()
{
	builtinTypeNames[0] = internString("int");
	builtinTypeNames[1] = internString("uint");
	builtinTypeNames[2] = internString("double");
	builtinTypeNames[3] = internString("idouble");
	builtinTypeNames[4] = internString("float");
	builtinTypeNames[5] = internString("ifloat");
	builtinTypeNames[6] = internString("short");
	builtinTypeNames[7] = internString("ushort");
	builtinTypeNames[8] = internString("long");
	builtinTypeNames[9] = internString("ulong");
	builtinTypeNames[10] = internString("char");
	builtinTypeNames[11] = internString("wchar");
	builtinTypeNames[12] = internString("dchar");
	builtinTypeNames[13] = internString("bool");
	builtinTypeNames[14] = internString("void");
	builtinTypeNames[15] = internString("cent");
	builtinTypeNames[16] = internString("ucent");
	builtinTypeNames[17] = internString("real");
	builtinTypeNames[18] = internString("ireal");
	builtinTypeNames[19] = internString("byte");
	builtinTypeNames[20] = internString("ubyte");
	builtinTypeNames[21] = internString("cdouble");
	builtinTypeNames[22] = internString("cfloat");
	builtinTypeNames[23] = internString("creal");

	IMPORT_SYMBOL_NAME = internString("public");
	WITH_SYMBOL_NAME = internString("with");
	CONSTRUCTOR_SYMBOL_NAME = internString("*constructor*");
	DESTRUCTOR_SYMBOL_NAME = internString("~this");
	ARGPTR_SYMBOL_NAME = internString("_argptr");
	ARGUMENTS_SYMBOL_NAME = internString("_arguments");
	THIS_SYMBOL_NAME = internString("this");
	UNITTEST_SYMBOL_NAME = internString("*unittest*");
	DOUBLE_LITERAL_SYMBOL_NAME = internString("*double");
	FLOAT_LITERAL_SYMBOL_NAME = internString("*float");
	IDOUBLE_LITERAL_SYMBOL_NAME = internString("*idouble");
	IFLOAT_LITERAL_SYMBOL_NAME = internString("*ifloat");
	INT_LITERAL_SYMBOL_NAME = internString("*int");
	LONG_LITERAL_SYMBOL_NAME = internString("*long");
	REAL_LITERAL_SYMBOL_NAME = internString("*real");
	IREAL_LITERAL_SYMBOL_NAME = internString("*ireal");
	UINT_LITERAL_SYMBOL_NAME = internString("*uint");
	ULONG_LITERAL_SYMBOL_NAME = internString("*ulong");
	CHAR_LITERAL_SYMBOL_NAME = internString("*char");
	DSTRING_LITERAL_SYMBOL_NAME = internString("*dstring");
	STRING_LITERAL_SYMBOL_NAME = internString("*string");
	WSTRING_LITERAL_SYMBOL_NAME = internString("*wstring");

	auto bool_ = allocate!ACSymbol(Mallocator.it, internString("bool"), CompletionKind.keyword);
	auto int_ = allocate!ACSymbol(Mallocator.it, internString("int"), CompletionKind.keyword);
	auto long_ = allocate!ACSymbol(Mallocator.it, internString("long"), CompletionKind.keyword);
	auto byte_ = allocate!ACSymbol(Mallocator.it, internString("byte"), CompletionKind.keyword);
	auto char_ = allocate!ACSymbol(Mallocator.it, internString("char"), CompletionKind.keyword);
	auto dchar_ = allocate!ACSymbol(Mallocator.it, internString("dchar"), CompletionKind.keyword);
	auto short_ = allocate!ACSymbol(Mallocator.it, internString("short"), CompletionKind.keyword);
	auto ubyte_ = allocate!ACSymbol(Mallocator.it, internString("ubyte"), CompletionKind.keyword);
	auto uint_ = allocate!ACSymbol(Mallocator.it, internString("uint"), CompletionKind.keyword);
	auto ulong_ = allocate!ACSymbol(Mallocator.it, internString("ulong"), CompletionKind.keyword);
	auto ushort_ = allocate!ACSymbol(Mallocator.it, internString("ushort"), CompletionKind.keyword);
	auto wchar_ = allocate!ACSymbol(Mallocator.it, internString("wchar"), CompletionKind.keyword);

	auto alignof_ = allocate!ACSymbol(Mallocator.it, internString("alignof"), CompletionKind.keyword);
	auto mangleof_ = allocate!ACSymbol(Mallocator.it, internString("mangleof"), CompletionKind.keyword);
	auto sizeof_ = allocate!ACSymbol(Mallocator.it, internString("sizeof"), CompletionKind.keyword);
	auto stringof_ = allocate!ACSymbol(Mallocator.it, internString("init"), CompletionKind.keyword);
	auto init = allocate!ACSymbol(Mallocator.it, internString("stringof"), CompletionKind.keyword);

	arraySymbols.insert(alignof_);
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("dup"), CompletionKind.keyword));
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("idup"), CompletionKind.keyword));
	arraySymbols.insert(init);
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("length"), CompletionKind.keyword, ulong_));
	arraySymbols.insert(mangleof_);
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("ptr"), CompletionKind.keyword));
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("reverse"), CompletionKind.keyword));
	arraySymbols.insert(sizeof_);
	arraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("sort"), CompletionKind.keyword));
	arraySymbols.insert(stringof_);

	assocArraySymbols.insert(alignof_);
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("byKey"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("byValue"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("dup"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("get"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("init"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("keys"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("length"), CompletionKind.keyword, ulong_));
	assocArraySymbols.insert(mangleof_);
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("rehash"), CompletionKind.keyword));
	assocArraySymbols.insert(sizeof_);
	assocArraySymbols.insert(stringof_);
	assocArraySymbols.insert(init);
	assocArraySymbols.insert(allocate!ACSymbol(Mallocator.it, internString("values"), CompletionKind.keyword));

	ACSymbol*[11] integralTypeArray;
	integralTypeArray[0] = bool_;
	integralTypeArray[1] = int_;
	integralTypeArray[2] = long_;
	integralTypeArray[3] = byte_;
	integralTypeArray[4] = char_;
	integralTypeArray[4] = dchar_;
	integralTypeArray[5] = short_;
	integralTypeArray[6] = ubyte_;
	integralTypeArray[7] = uint_;
	integralTypeArray[8] = ulong_;
	integralTypeArray[9] = ushort_;
	integralTypeArray[10] = wchar_;

	foreach (s; integralTypeArray)
	{
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("init"), CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("min"), CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("max"), CompletionKind.keyword, s));
		s.parts.insert(alignof_);
		s.parts.insert(sizeof_);
		s.parts.insert(stringof_);
		s.parts.insert(mangleof_);
		s.parts.insert(init);
	}

	auto cdouble_ = allocate!ACSymbol(Mallocator.it, internString("cdouble"), CompletionKind.keyword);
	auto cent_ = allocate!ACSymbol(Mallocator.it, internString("cent"), CompletionKind.keyword);
	auto cfloat_ = allocate!ACSymbol(Mallocator.it, internString("cfloat"), CompletionKind.keyword);
	auto creal_ = allocate!ACSymbol(Mallocator.it, internString("creal"), CompletionKind.keyword);
	auto double_ = allocate!ACSymbol(Mallocator.it, internString("double"), CompletionKind.keyword);
	auto float_ = allocate!ACSymbol(Mallocator.it, internString("float"), CompletionKind.keyword);
	auto idouble_ = allocate!ACSymbol(Mallocator.it, internString("idouble"), CompletionKind.keyword);
	auto ifloat_ = allocate!ACSymbol(Mallocator.it, internString("ifloat"), CompletionKind.keyword);
	auto ireal_ = allocate!ACSymbol(Mallocator.it, internString("ireal"), CompletionKind.keyword);
	auto real_ = allocate!ACSymbol(Mallocator.it, internString("real"), CompletionKind.keyword);
	auto ucent_ = allocate!ACSymbol(Mallocator.it, internString("ucent"), CompletionKind.keyword);

	ACSymbol*[11] floatTypeArray;
	floatTypeArray[0] = cdouble_;
	floatTypeArray[1] = cent_;
	floatTypeArray[2] = cfloat_;
	floatTypeArray[3] = creal_;
	floatTypeArray[4] = double_;
	floatTypeArray[5] = float_;
	floatTypeArray[6] = idouble_;
	floatTypeArray[7] = ifloat_;
	floatTypeArray[8] = ireal_;
	floatTypeArray[9] = real_;
	floatTypeArray[10] = ucent_;

	foreach (s; floatTypeArray)
	{
		s.parts.insert(alignof_);
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("dig"), CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("epsilon"), CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("infinity"), CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("init"), CompletionKind.keyword, s));
		s.parts.insert(mangleof_);
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("mant_dig"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("max"), CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("max_10_exp"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("max_exp"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("min"), CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("min_exp"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("min_10_exp"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("min_normal"), CompletionKind.keyword, s));
		s.parts.insert(allocate!ACSymbol(Mallocator.it, internString("nan"), CompletionKind.keyword, s));
		s.parts.insert(sizeof_);
		s.parts.insert(stringof_);
	}

	aggregateSymbols.insert(allocate!ACSymbol(Mallocator.it, internString("tupleof"), CompletionKind.keyword));
	aggregateSymbols.insert(mangleof_);
	aggregateSymbols.insert(alignof_);
	aggregateSymbols.insert(sizeof_);
	aggregateSymbols.insert(stringof_);
	aggregateSymbols.insert(init);

	classSymbols.insert(allocate!ACSymbol(Mallocator.it, internString("classInfo"), CompletionKind.variableName));
	classSymbols.insert(allocate!ACSymbol(Mallocator.it, internString("tupleof"), CompletionKind.variableName));
	classSymbols.insert(allocate!ACSymbol(Mallocator.it, internString("__vptr"), CompletionKind.variableName));
	classSymbols.insert(allocate!ACSymbol(Mallocator.it, internString("__monitor"), CompletionKind.variableName));
	classSymbols.insert(mangleof_);
	classSymbols.insert(alignof_);
	classSymbols.insert(sizeof_);
	classSymbols.insert(stringof_);
	classSymbols.insert(init);

	ireal_.parts.insert(allocate!ACSymbol(Mallocator.it, internString("im"), CompletionKind.keyword, real_));
	ifloat_.parts.insert(allocate!ACSymbol(Mallocator.it, internString("im"), CompletionKind.keyword, float_));
	idouble_.parts.insert(allocate!ACSymbol(Mallocator.it, internString("im"), CompletionKind.keyword, double_));
	ireal_.parts.insert(allocate!ACSymbol(Mallocator.it, internString("re"), CompletionKind.keyword, real_));
	ifloat_.parts.insert(allocate!ACSymbol(Mallocator.it, internString("re"), CompletionKind.keyword, float_));
	idouble_.parts.insert(allocate!ACSymbol(Mallocator.it, internString("re"), CompletionKind.keyword, double_));

	auto void_ = allocate!ACSymbol(Mallocator.it, internString("void"), CompletionKind.keyword);

	builtinSymbols.insert(bool_);
	bool_.type = bool_;
	builtinSymbols.insert(int_);
	int_.type = int_;
	builtinSymbols.insert(long_);
	long_.type = long_;
	builtinSymbols.insert(byte_);
	byte_.type = byte_;
	builtinSymbols.insert(char_);
	char_.type = char_;
	builtinSymbols.insert(dchar_);
	dchar_.type = dchar_;
	builtinSymbols.insert(short_);
	short_.type = short_;
	builtinSymbols.insert(ubyte_);
	ubyte_.type = ubyte_;
	builtinSymbols.insert(uint_);
	uint_.type = uint_;
	builtinSymbols.insert(ulong_);
	ulong_.type = ulong_;
	builtinSymbols.insert(ushort_);
	ushort_.type = ushort_;
	builtinSymbols.insert(wchar_);
	wchar_.type = wchar_;
	builtinSymbols.insert(cdouble_);
	cdouble_.type = cdouble_;
	builtinSymbols.insert(cent_);
	cent_.type = cent_;
	builtinSymbols.insert(cfloat_);
	cfloat_.type = cfloat_;
	builtinSymbols.insert(creal_);
	creal_.type = creal_;
	builtinSymbols.insert(double_);
	double_.type = double_;
	builtinSymbols.insert(float_);
	float_.type = float_;
	builtinSymbols.insert(idouble_);
	idouble_.type = idouble_;
	builtinSymbols.insert(ifloat_);
	ifloat_.type = ifloat_;
	builtinSymbols.insert(ireal_);
	ireal_.type = ireal_;
	builtinSymbols.insert(real_);
	real_.type = real_;
	builtinSymbols.insert(ucent_);
	ucent_.type = ucent_;
	builtinSymbols.insert(void_);
	void_.type = void_;
}

