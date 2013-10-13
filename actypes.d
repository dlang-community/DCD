/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2013 Brian Schott
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

import stdx.d.lexer;
import stdx.d.ast;
import std.algorithm;
import std.stdio;
import std.array;
import messages;
import std.array;
import std.typecons;

/**
 * Any special information about a variable declaration symbol.
 */
enum SymbolQualifier : ubyte
{
	/// _none
	none,
	/// the symbol is an _array
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
	 * Params:
	 *     name = the symbol's name
	 */
	this(string name)
	{
		this.name = name;
	}

	/**
	 * Params:
	 *     name = the symbol's name
	 *     kind = the symbol's completion kind
	 */
	this(string name, CompletionKind kind)
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
	this(string name, CompletionKind kind, const(ACSymbol)* type)
	{
		this.name = name;
		this.kind = kind;
		this.type = type;
	}

    /**
     * Comparison operator sorts based on the name field
     */
    int opCmp(string str) const
    {
        if (str < this.name) return -1;
        if (str > this.name) return 1;
        return 0;
    }

    /// ditto
    int opCmp(const(ACSymbol)* other) const
    {
        return this.opCmp(other.name);
    }

	/**
	 * Gets all parts whose name matches the given string.
	 */
	const(ACSymbol)*[] getPartsByName(string name) const
	{
		return cast(typeof(return)) parts.filter!(a => a.name == name).array;
	}

	size_t estimateMemory(size_t runningTotal) const
	{
		runningTotal = runningTotal + name.length + callTip.length
			+ ACSymbol.sizeof;
		foreach (part; parts)
			runningTotal = part.estimateMemory(runningTotal);
		return runningTotal;
	}

	/**
	 * Symbols that compose this symbol, such as enum members, class variables,
	 * methods, etc.
	 */
	const(ACSymbol)*[] parts;

	/**
	 * Symbol's name
	 */
	string name;

	/**
	 * Calltip to display if this is a function
	 */
	string callTip;

	/**
	 * Module containing the symbol.
	 */
	string symbolFile;

	/**
	 * The symbol that represents the type.
	 */
	const(ACSymbol)* type;

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

struct Scope
{
	Scope* getScopeByCursor(size_t cursorPosition) const
	{
		if (cursorPosition < startLocation) return null;
		if (cursorPosition > endLocation) return null;
		foreach (child; children)
		{
			auto childScope = child.getScopeByCursor(cursorPosition);
			if (childScope !is null)
				return childScope;
		}
		return cast(typeof(return)) &this;
	}

	ACSymbol*[] getSymbolsInCursorScope(size_t cursorPosition) const
	{
		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		return cast(typeof(return)) s.symbols;
	}

	const(ACSymbol)*[] getSymbolsByName(string name) const
	{
		const(ACSymbol)*[] retVal = cast(typeof(return)) symbols.filter!(a => a.name == name).array();
		if (retVal.length > 0)
			return retVal;
		if (parent is null)
			return [];
		return parent.getSymbolsByName(name);
	}

	const(ACSymbol)*[] getSymbolsByNameAndCursor(string name, size_t cursorPosition) const
	{
		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		return s.getSymbolsByName(name);
	}

	const(ACSymbol)*[] symbols;
	ImportInformation[] importInformation;
	Scope* parent;
	Scope*[] children;
	size_t startLocation;
	size_t endLocation;
}

struct ImportInformation
{
	/// module relative path
	string modulePath;
	/// symbols to import from this module
	Tuple!(string, string)[] importedSymbols;
	/// true if the import is public
	bool isPublic;
}


/**
 * Initializes builtin types and the various properties of builtin types
 */
static this()
{
    // TODO: make sure all parts are sorted.
	auto bool_ = new ACSymbol("bool", CompletionKind.keyword);
	auto int_ = new ACSymbol("int", CompletionKind.keyword);
	auto long_ = new ACSymbol("long", CompletionKind.keyword);
	auto byte_ = new ACSymbol("byte", CompletionKind.keyword);
	auto char_ = new ACSymbol("char", CompletionKind.keyword);
	auto dchar_ = new ACSymbol("dchar", CompletionKind.keyword);
	auto short_ = new ACSymbol("short", CompletionKind.keyword);
	auto ubyte_ = new ACSymbol("ubyte", CompletionKind.keyword);
	auto uint_ = new ACSymbol("uint", CompletionKind.keyword);
	auto ulong_ = new ACSymbol("ulong", CompletionKind.keyword);
	auto ushort_ = new ACSymbol("ushort", CompletionKind.keyword);
	auto wchar_ = new ACSymbol("wchar", CompletionKind.keyword);

	auto alignof_ = new ACSymbol("alignof", CompletionKind.keyword, ulong_);
	auto mangleof_ = new ACSymbol("mangleof", CompletionKind.keyword);
	auto sizeof_ = new ACSymbol("sizeof", CompletionKind.keyword, ulong_);
	auto stringof_ = new ACSymbol("stringof", CompletionKind.keyword);

	arraySymbols ~= alignof_;
	arraySymbols ~= new ACSymbol("dup", CompletionKind.keyword);
	arraySymbols ~= new ACSymbol("idup", CompletionKind.keyword);
	arraySymbols ~= new ACSymbol("init", CompletionKind.keyword);
	arraySymbols ~= new ACSymbol("length", CompletionKind.keyword, ulong_);
	arraySymbols ~= mangleof_;
	arraySymbols ~= new ACSymbol("ptr", CompletionKind.keyword);
	arraySymbols ~= new ACSymbol("reverse", CompletionKind.keyword);
	arraySymbols ~= sizeof_;
	arraySymbols ~= new ACSymbol("sort", CompletionKind.keyword);
	arraySymbols ~= stringof_;
    arraySymbols.sort();

	assocArraySymbols ~= alignof_;
	assocArraySymbols ~= new ACSymbol("byKey", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("byValue", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("dup", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("get", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("init", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("keys", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("length", CompletionKind.keyword, ulong_);
	assocArraySymbols ~= mangleof_;
	assocArraySymbols ~= new ACSymbol("rehash", CompletionKind.keyword);
	assocArraySymbols ~= sizeof_;
	assocArraySymbols ~= stringof_;
	assocArraySymbols ~= new ACSymbol("values", CompletionKind.keyword);
	assocArraySymbols.sort();

	foreach (s; [bool_, int_, long_, byte_, char_, dchar_, short_, ubyte_, uint_,
		ulong_, ushort_, wchar_])
	{
		s.parts ~= new ACSymbol("init", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("min", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("max", CompletionKind.keyword, s);
		s.parts ~= alignof_;
		s.parts ~= sizeof_;
		s.parts ~= stringof_;
		s.parts ~= mangleof_;
	}

	auto cdouble_ = new ACSymbol("cdouble", CompletionKind.keyword);
	auto cent_ = new ACSymbol("cent", CompletionKind.keyword);
	auto cfloat_ = new ACSymbol("cfloat", CompletionKind.keyword);
	auto creal_ = new ACSymbol("creal", CompletionKind.keyword);
	auto double_ = new ACSymbol("double", CompletionKind.keyword);
	auto float_ = new ACSymbol("float", CompletionKind.keyword);
	auto idouble_ = new ACSymbol("idouble", CompletionKind.keyword);
	auto ifloat_ = new ACSymbol("ifloat", CompletionKind.keyword);
	auto ireal_ = new ACSymbol("ireal", CompletionKind.keyword);
	auto real_ = new ACSymbol("real", CompletionKind.keyword);
	auto ucent_ = new ACSymbol("ucent", CompletionKind.keyword);

	foreach (s; [cdouble_, cent_, cfloat_, creal_, double_, float_,
		idouble_, ifloat_, ireal_, real_, ucent_])
	{
		s.parts ~= alignof_;
		s.parts ~= new ACSymbol("dig", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("epsilon", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("infinity", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("init", CompletionKind.keyword, s);
		s.parts ~= mangleof_;
		s.parts ~= new ACSymbol("mant_dig", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("max", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("max_10_exp", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("max_exp", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("min", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("min_exp", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("min_10_exp", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("min_normal", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("nan", CompletionKind.keyword, s);
		s.parts ~= sizeof_;
		s.parts ~= stringof_;
	}

	ireal_.parts ~= new ACSymbol("im", CompletionKind.keyword, real_);
	ifloat_.parts ~= new ACSymbol("im", CompletionKind.keyword, float_);
	idouble_.parts ~= new ACSymbol("im", CompletionKind.keyword, double_);
	ireal_.parts ~= new ACSymbol("re", CompletionKind.keyword, real_);
	ifloat_.parts ~= new ACSymbol("re", CompletionKind.keyword, float_);
	idouble_.parts ~= new ACSymbol("re", CompletionKind.keyword, double_);

	auto void_ = new ACSymbol("void", CompletionKind.keyword);

	builtinSymbols = [bool_, int_, long_, byte_, char_, dchar_, short_, ubyte_, uint_,
		ulong_, ushort_, wchar_, cdouble_, cent_, cfloat_, creal_, double_,
		float_, idouble_, ifloat_, ireal_, real_, ucent_, void_];

	// _argptr has type void*
	argptrType = new Type;
	argptrType.type2 = new Type2;
	argptrType.type2.builtinType = TokenType.void_;
	TypeSuffix argptrTypeSuffix = new TypeSuffix;
	argptrTypeSuffix.star = true;
	argptrType.typeSuffixes ~= argptrTypeSuffix;

	// _arguments has type TypeInfo[]
	argumentsType = new Type;
	argumentsType = new Type;
	argumentsType.type2 = new Type2;
	argumentsType.type2.symbol = new Symbol;
	argumentsType.type2.symbol.identifierOrTemplateChain = new IdentifierOrTemplateChain;
	IdentifierOrTemplateInstance i = new IdentifierOrTemplateInstance;
	i.identifier.value = "TypeInfo";
	i.identifier.type = TokenType.identifier;
	argumentsType.type2.symbol.identifierOrTemplateChain.identifiersOrTemplateInstances ~= i;
	TypeSuffix argumentsTypeSuffix = new TypeSuffix;
	argumentsTypeSuffix.array = true;
	argumentsType.typeSuffixes ~= argptrTypeSuffix;
}

const(ACSymbol)*[] builtinSymbols;
const(ACSymbol)*[] arraySymbols;
const(ACSymbol)*[] assocArraySymbols;
const(ACSymbol)*[] classSymbols;
const(ACSymbol)*[] structSymbols;
Type argptrType;
Type argumentsType;
