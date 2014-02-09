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

import stdx.d.lexer;
import stdx.d.ast;
import std.algorithm;
import std.stdio;
import std.array;
import messages;
import std.array;
import std.typecons;
import std.container;

/**
 * Compares symbols by their name
 */
bool comparitor(const(ACSymbol)* a, const(ACSymbol)* b) pure nothrow
{
	return a.name < b.name;
}

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

	@disable this();

	/**
	 * Params:
	 *     name = the symbol's name
	 */
	this(string name)
	{
		this.name = name;
		this.parts = new RedBlackTree!(ACSymbol*, comparitor, true);
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
		this.parts = new RedBlackTree!(ACSymbol*, comparitor, true);
	}

	/**
	 * Params:
	 *     name = the symbol's name
	 *     kind = the symbol's completion kind
	 *     resolvedType = the resolved type of the symbol
	 */
	this(string name, CompletionKind kind, ACSymbol* type)
	{
		this.name = name;
		this.kind = kind;
		this.type = type;
		this.parts = new RedBlackTree!(ACSymbol*, comparitor, true);
	}

	/**
	 * Gets all parts whose name matches the given string.
	 */
	ACSymbol*[] getPartsByName(string name)
	{
		import std.range;
		ACSymbol s = ACSymbol(name);
		return parts.equalRange(&s).array();
	}

	/**
	 * Symbols that compose this symbol, such as enum members, class variables,
	 * methods, etc.
	 */
	RedBlackTree!(ACSymbol*, comparitor, true) parts;

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
	 * Documentation for the symbol.
	 */
	string doc;

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
		this.symbols = new RedBlackTree!(ACSymbol*, comparitor, true);
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
		foreach (child; children)
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
		auto symbols = s.symbols;
		Scope* sc = s.parent;
		while (sc !is null)
		{
			foreach (sym; sc.symbols)
				symbols.insert(sym);
			sc = sc.parent;
		}
		return symbols.array();
	}

	/**
	 * Params:
	 *     name = the symbol name to search for
	 * Returns:
	 *     all symbols in this scope or parent scopes with the given name
	 */
	ACSymbol*[] getSymbolsByName(string name) const
	{
		import std.range;
		ACSymbol s = ACSymbol(name);
		RedBlackTree!(ACSymbol*, comparitor, true) t = cast() symbols;
		auto r = t.equalRange(&s).array();
		if (r.length > 0)
			return cast(typeof(return)) r;
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
	ACSymbol*[] getSymbolsByNameAndCursor(string name, size_t cursorPosition) const
	{
		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		return s.getSymbolsByName(name);
	}

	/// Imports contained in this scope
	ImportInformation[] importInformation;

	/// The scope that contains this one
	Scope* parent;

	/// Child scopes
	Scope*[] children;

	/// Start location of this scope in bytes
	size_t startLocation;

	/// End location of this scope in bytes
	size_t endLocation;

	/// Symbols contained in this scope
	RedBlackTree!(ACSymbol*, comparitor, true) symbols;
}

/**
 * Import information
 */
struct ImportInformation
{
	/// Import statement parts
	string[] importParts;
	/// module relative path
	string modulePath;
	/// symbols to import from this module
	Tuple!(string, string)[] importedSymbols;
	/// true if the import is public
	bool isPublic;
}


/**
 * Symbols for the built in types
 */
RedBlackTree!(ACSymbol*, comparitor, true) builtinSymbols;

/**
 * Array properties
 */
RedBlackTree!(ACSymbol*, comparitor, true) arraySymbols;

/**
 * Associative array properties
 */
RedBlackTree!(ACSymbol*, comparitor, true) assocArraySymbols;

/**
 * Enum, union, class, and interface properties
 */
RedBlackTree!(ACSymbol*, comparitor, true) aggregateSymbols;

/**
 * Class properties
 */
RedBlackTree!(ACSymbol*, comparitor, true) classSymbols;

/**
 * Type of the _argptr variable
 */
Type argptrType;

/**
 * Type of _arguments
 */
Type argumentsType;

/**
 * Initializes builtin types and the various properties of builtin types
 */
static this()
{
	auto bSym = new RedBlackTree!(ACSymbol*, comparitor, true);
	auto arrSym = new RedBlackTree!(ACSymbol*, comparitor, true);
	auto asarrSym = new RedBlackTree!(ACSymbol*, comparitor, true);
	auto aggSym = new RedBlackTree!(ACSymbol*, comparitor, true);
	auto clSym = new RedBlackTree!(ACSymbol*, comparitor, true);

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
	auto stringof_ = new ACSymbol("init", CompletionKind.keyword);
	auto init = new ACSymbol("stringof", CompletionKind.keyword);

	arrSym.insert(alignof_);
	arrSym.insert(new ACSymbol("dup", CompletionKind.keyword));
	arrSym.insert(new ACSymbol("idup", CompletionKind.keyword));
	arrSym.insert(init);
	arrSym.insert(new ACSymbol("length", CompletionKind.keyword, ulong_));
	arrSym.insert(mangleof_);
	arrSym.insert(new ACSymbol("ptr", CompletionKind.keyword));
	arrSym.insert(new ACSymbol("reverse", CompletionKind.keyword));
	arrSym.insert(sizeof_);
	arrSym.insert(new ACSymbol("sort", CompletionKind.keyword));
	arrSym.insert(stringof_);

	asarrSym.insert(alignof_);
	asarrSym.insert(new ACSymbol("byKey", CompletionKind.keyword));
	asarrSym.insert(new ACSymbol("byValue", CompletionKind.keyword));
	asarrSym.insert(new ACSymbol("dup", CompletionKind.keyword));
	asarrSym.insert(new ACSymbol("get", CompletionKind.keyword));
	asarrSym.insert(new ACSymbol("init", CompletionKind.keyword));
	asarrSym.insert(new ACSymbol("keys", CompletionKind.keyword));
	asarrSym.insert(new ACSymbol("length", CompletionKind.keyword, ulong_));
	asarrSym.insert(mangleof_);
	asarrSym.insert(new ACSymbol("rehash", CompletionKind.keyword));
	asarrSym.insert(sizeof_);
	asarrSym.insert(stringof_);
	asarrSym.insert(init);
	asarrSym.insert(new ACSymbol("values", CompletionKind.keyword));

	foreach (s; [bool_, int_, long_, byte_, char_, dchar_, short_, ubyte_, uint_,
		ulong_, ushort_, wchar_])
	{
		s.parts.insert(new ACSymbol("init", CompletionKind.keyword, s));
		s.parts.insert(new ACSymbol("min", CompletionKind.keyword, s));
		s.parts.insert(new ACSymbol("max", CompletionKind.keyword, s));
		s.parts.insert(alignof_);
		s.parts.insert(sizeof_);
		s.parts.insert(stringof_);
		s.parts.insert(mangleof_);
		s.parts.insert(init);
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
		s.parts.insert(alignof_);
		s.parts.insert(new ACSymbol("dig", CompletionKind.keyword, s));
		s.parts.insert(new ACSymbol("epsilon", CompletionKind.keyword, s));
		s.parts.insert(new ACSymbol("infinity", CompletionKind.keyword, s));
		s.parts.insert(new ACSymbol("init", CompletionKind.keyword, s));
		s.parts.insert(mangleof_);
		s.parts.insert(new ACSymbol("mant_dig", CompletionKind.keyword, int_));
		s.parts.insert(new ACSymbol("max", CompletionKind.keyword, s));
		s.parts.insert(new ACSymbol("max_10_exp", CompletionKind.keyword, int_));
		s.parts.insert(new ACSymbol("max_exp", CompletionKind.keyword, int_));
		s.parts.insert(new ACSymbol("min", CompletionKind.keyword, s));
		s.parts.insert(new ACSymbol("min_exp", CompletionKind.keyword, int_));
		s.parts.insert(new ACSymbol("min_10_exp", CompletionKind.keyword, int_));
		s.parts.insert(new ACSymbol("min_normal", CompletionKind.keyword, s));
		s.parts.insert(new ACSymbol("nan", CompletionKind.keyword, s));
		s.parts.insert(sizeof_);
		s.parts.insert(stringof_);
	}

	aggSym.insert(new ACSymbol("tupleof", CompletionKind.variableName));
	aggSym.insert(mangleof_);
	aggSym.insert(alignof_);
	aggSym.insert(sizeof_);
	aggSym.insert(stringof_);
	aggSym.insert(init);

	clSym.insert(new ACSymbol("classInfo", CompletionKind.variableName));
	clSym.insert(new ACSymbol("tupleof", CompletionKind.variableName));
	clSym.insert(new ACSymbol("__vptr", CompletionKind.variableName));
	clSym.insert(new ACSymbol("__monitor", CompletionKind.variableName));
	clSym.insert(mangleof_);
	clSym.insert(alignof_);
	clSym.insert(sizeof_);
	clSym.insert(stringof_);
	clSym.insert(init);

	ireal_.parts.insert(new ACSymbol("im", CompletionKind.keyword, real_));
	ifloat_.parts.insert(new ACSymbol("im", CompletionKind.keyword, float_));
	idouble_.parts.insert(new ACSymbol("im", CompletionKind.keyword, double_));
	ireal_.parts.insert(new ACSymbol("re", CompletionKind.keyword, real_));
	ifloat_.parts.insert(new ACSymbol("re", CompletionKind.keyword, float_));
	idouble_.parts.insert(new ACSymbol("re", CompletionKind.keyword, double_));

	auto void_ = new ACSymbol("void", CompletionKind.keyword);

	bSym.insert([bool_, int_, long_, byte_, char_, dchar_, short_, ubyte_, uint_,
		ulong_, ushort_, wchar_, cdouble_, cent_, cfloat_, creal_, double_,
		float_, idouble_, ifloat_, ireal_, real_, ucent_, void_]);

	// _argptr has type void*
	argptrType = new Type;
	argptrType.type2 = new Type2;
	argptrType.type2.builtinType = tok!"void";
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
	i.identifier.text = "TypeInfo";
	i.identifier.type = tok!"identifier";
	argumentsType.type2.symbol.identifierOrTemplateChain.identifiersOrTemplateInstances ~= i;
	TypeSuffix argumentsTypeSuffix = new TypeSuffix;
	argumentsTypeSuffix.array = true;
	argumentsType.typeSuffixes ~= argptrTypeSuffix;

	builtinSymbols = bSym;
	arraySymbols = arrSym;
	assocArraySymbols = asarrSym;
	aggregateSymbols = aggSym;
	classSymbols = clSym;
}

