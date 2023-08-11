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

import std.array;

import std.experimental.allocator.mallocator : Mallocator;
import std.experimental.allocator.gc_allocator : GCAllocator;
import containers.ttree;
import containers.unrolledlist;
import containers.slist;
import containers.hashset;
import dparse.lexer;
import std.bitmanip;

import dsymbol.builtin.names;
public import dsymbol.string_interning;

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

	/// UFCS function
	ufcsName = 'F',

	/// enum name
	enumName = 'g',

	/// enum member
	enumMember = 'e',

	/// package name
	packageName = 'P',

	/// module name
	moduleName = 'M',

	/// alias name
	aliasName = 'l',

	/// template name
	templateName = 't',

	/// mixin template name
	mixinTemplateName = 'T',

	/// variadic template parameter
	variadicTmpParam = 'p',

	/// type template parameter when no constraint
	typeTmpParam = 'h',
}

/**
 * Returns: true if `kind` is something that can be returned to the client
 */
bool isPublicCompletionKind(CompletionKind kind) pure nothrow @safe @nogc
{
	return kind != CompletionKind.dummy && kind != CompletionKind.importSymbol
		&& kind != CompletionKind.withSymbol;
}


/**
 * Any special information about a variable declaration symbol.
 */
enum SymbolQualifier : ubyte
{
	/// None
	none,
	/// The symbol is an array
	array,
	/// The symbol is a associative array
	assocArray,
	/// The symbol is a function or delegate pointer
	func,
	/// Selective import
	selectiveImport,
	/// The symbol is a pointer
	pointer,
	/// The symbol is templated
	templated,
}

/**
 * Autocompletion symbol
 */
struct DSymbol
{
	// Copying is disabled
	@disable this();
	@disable this(this);

	/**
	 * Params:
	 *     name = the symbol's name
	 *     kind = the symbol's completion kind
	 *     type = the resolved type of the symbol
	 */
	this(string name, CompletionKind kind = CompletionKind.dummy, DSymbol* type = null) nothrow @nogc @safe
	{
		this.name = istring(name);
		this.kind = kind;
		this.type = type;
	}
	/// ditto
	this(istring name, CompletionKind kind = CompletionKind.dummy, DSymbol* type = null) nothrow @nogc @safe
	{
		this.name = name;
		this.kind = kind;
		this.type = type;
	}

	~this()
	{
		foreach (ref part; parts[])
		{
			if (part.owned)
			{
				assert(part.ptr !is null);
				typeid(DSymbol).destroy(part.ptr);
			}
			else
				part.ptr = null;
		}
		if (ownType)
			typeid(DSymbol).destroy(type);
	}

	ptrdiff_t opCmp(ref const DSymbol other) const pure nothrow @nogc @safe
	{
		return name.opCmpFast(other.name);
	}

	bool opEquals(ref const DSymbol other) const pure nothrow @nogc @safe
	{
		return name == other.name;
	}

	size_t toHash() const pure nothrow @nogc @safe
	{
		return name.toHash();
	}

	/**
	 * Gets all parts whose name matches the given string.
	 */
	inout(DSymbol)*[] getPartsByName(istring name) inout
	{
		auto app = appender!(DSymbol*[])();
		HashSet!size_t visited;
		getParts(name, app, visited);
		return cast(typeof(return)) app.data;
	}

	inout(DSymbol)* getFirstPartNamed(this This)(istring name) inout
	{
		auto app = appender!(DSymbol*[])();
		HashSet!size_t visited;
		getParts(name, app, visited);
		return app.data.length > 0 ? cast(typeof(return)) app.data[0] : null;
	}

	/**
	 * Gets all parts and imported parts. Filters based on the part's name if
	 * the `name` argument is not null. Stores results in `app`.
	 */
	void getParts(OR)(istring name, ref OR app, ref HashSet!size_t visited,
			bool onlyOne = false) inout
		if (isOutputRange!(OR, DSymbol*))
	{
		import std.algorithm.iteration : filter;

		if (&this is null)
			return;
		if (visited.contains(cast(size_t) &this))
			return;
		visited.insert(cast(size_t) &this);

		// pointers are implicitly dereferenced on members (a single layer)
		if (qualifier == SymbolQualifier.pointer
			&& this.type.qualifier != SymbolQualifier.pointer)
			return type.getParts!OR(name, app, visited, onlyOne);

		if (name is null)
		{
			foreach (part; parts[].filter!(a => a.name != IMPORT_SYMBOL_NAME))
			{
				app.put(cast(DSymbol*) part);
				if (onlyOne)
					return;
			}
			DSymbol p = DSymbol(IMPORT_SYMBOL_NAME);
			foreach (im; parts.equalRange(SymbolOwnership(&p)))
			{
				if (im.type !is null && !im.skipOver)
				{
					if (im.qualifier == SymbolQualifier.selectiveImport)
					{
						app.put(cast(DSymbol*) im.type);
						if (onlyOne)
							return;
					}
					else
						im.type.getParts(name, app, visited, onlyOne);
				}
			}
		}
		else
		{
			DSymbol s = DSymbol(name);
			foreach (part; parts.equalRange(SymbolOwnership(&s)))
			{
				app.put(cast(DSymbol*) part);
				if (onlyOne)
					return;
			}
			if (name == CONSTRUCTOR_SYMBOL_NAME ||
				name == DESTRUCTOR_SYMBOL_NAME ||
				name == UNITTEST_SYMBOL_NAME ||
				name == THIS_SYMBOL_NAME)
				return;	// these symbols should not be imported

			DSymbol p = DSymbol(IMPORT_SYMBOL_NAME);
			foreach (im; parts.equalRange(SymbolOwnership(&p)))
			{
				if (im.type !is null && !im.skipOver)
				{
					if (im.qualifier == SymbolQualifier.selectiveImport)
					{
						if (im.type.name == name)
						{
							app.put(cast(DSymbol*) im.type);
							if (onlyOne)
								return;
						}
					}
					else
						im.type.getParts(name, app, visited, onlyOne);
				}
			}
		}
	}

	/**
	 * Returns: a range over this symbol's parts and publicly visible imports
	 */
	inout(DSymbol)*[] opSlice(this This)() inout
	{
		auto app = appender!(DSymbol*[])();
		HashSet!size_t visited;
		getParts!(typeof(app))(istring(null), app, visited);
		return cast(typeof(return)) app.data;
	}

	void addChild(DSymbol* symbol, bool owns)
	{
		assert(symbol !is null);
		parts.insert(SymbolOwnership(symbol, owns));
	}

	void addChildren(R)(R symbols, bool owns)
	{
		foreach (symbol; symbols)
		{
			assert(symbol !is null);
			parts.insert(SymbolOwnership(symbol, owns));
		}
	}

	void addChildren(DSymbol*[] symbols, bool owns)
	{
		foreach (symbol; symbols)
		{
			assert(symbol !is null);
			parts.insert(SymbolOwnership(symbol, owns));
		}
	}

	/**
	 * Updates the type field based on the mappings contained in the given
	 * collection.
	 */
	void updateTypes(ref UpdatePairCollection collection)
	{
		auto r = collection.equalRange(UpdatePair(type, null));
		if (!r.empty)
			type = r.front.newSymbol;
		foreach (part; parts[])
			part.updateTypes(collection);
	}

	/**
	 * Symbols that compose this symbol, such as enum members, class variables,
	 * methods, parameters, etc.
	 */
	alias PartsAllocator = GCAllocator; // NOTE using `Mallocator` here fails when analysing Phobos
	alias Parts = TTree!(SymbolOwnership, PartsAllocator, true, "a < b");
	private Parts parts;

	/**
	 * DSymbol's name
	 */
	istring name;

	/**
	 * Calltip to display if this is a function
	 */
	istring callTip;

	/**
	 * Used for storing information for selective renamed imports
	 */
	alias altFile = callTip;

	/**
	 * Module containing the symbol.
	 */
	istring symbolFile;

	/**
	 * Documentation for the symbol.
	 */
	DocString doc;

	/**
	 * The symbol that represents the type.
	 */
	// TODO: assert that the type is not a function
	DSymbol* type;

	// Is alias this symbols
	DSymbol*[] aliasThisSymbols;
	/**
	 * Names of function arguments
	 */
	// TODO: remove since we have function arguments
	UnrolledList!(istring) argNames;

	/**
	 * Function parameter symbols
	 */
	DSymbol*[] functionParameters;

	/**
	 * Used to resolve the type
	 */
	istring typeSymbolName;

	private uint _location;

	/**
	 * DSymbol location
	 */
	size_t location() const pure nothrow @nogc @property @safe
	{
		return _location;
	}

	void location(size_t location) pure nothrow @nogc @property @safe
	{
		// If the symbol was declared in a file, assert that it has a location
		// in that file. Built-in symbols don't need a location.
		assert(symbolFile is null || location < uint.max);
		_location = cast(uint) location;
	}

	/**
	 * The kind of symbol
	 */
	CompletionKind kind;

	/**
	 * DSymbol qualifier
	 */
	SymbolQualifier qualifier;

	/**
	 * If true, this symbol owns its type and will free it on destruction
	 */
	// dfmt off
	mixin(bitfields!(
		bool, "ownType", 1,
		bool, "skipOver", 1,
		bool, "_flag0", 1, // planned: const/immutable/shared/inout for types and parameters
		bool, "_flag1", 1,
		bool, "_flag2", 1,
		bool, "_flag3", 1,
		bool, "_flag4", 1,
		bool, "_flag5", 1,
		bool, "_flag6", 1,
		bool, "_flag7", 1,
		bool, "_flag8", 1,
		bool, "_flag9", 1,
		bool, "_flag10", 1,
		uint, "", 3,
	));
	// dfmt on

	/// Only valid for parameters: the parameter has storage class `ref` (not `auto ref`)
	alias parameterIsRef = _flag4;
	/// Only valid for parameters: the parameter has storage class `auto ref` (not `ref`)
	alias parameterIsAutoRef = _flag5;
	// TODO: maybe parameterIsScope and parameterIsReturn need to be differentiated for `scope return` and `return scope`?
	// unsure about the needed semantics here.
	/// Only valid for parameters: the parameter has storage class `scope`
	alias parameterIsScope = _flag6;
	/// Only valid for parameters: the parameter has storage class `return`
	alias parameterIsReturn = _flag7;
	/// Only valid for parameters: the parameter has storage class `lazy`
	alias parameterIsLazy = _flag8;
	/// Only valid for parameters: the parameter has storage class `out`
	alias parameterIsOut = _flag9;
	/// Only valid for parameters: the parameter has storage class `in`
	alias parameterIsIn = _flag10;

	deprecated bool isPointer()
	{
		return qualifier == SymbolQualifier.pointer;
	}

	/// Protection level for this symbol
	IdType protection;

	string formatType(string suffix = "") const
	{
		if (kind == CompletionKind.functionName)
		{
			if (type) // try to give return type symbol
				return type.formatType;
			else // null if unresolved, user can manually pick .name or .callTip if needed
				return null;
		}
		else if (name == POINTER_SYMBOL_NAME)
		{
			if (!type)
				return suffix ~ "*";
			else
				return type.formatType(suffix ~ "*");
		}
		else if (name == ARRAY_SYMBOL_NAME)
		{
			if (!type)
				return suffix ~ "[]";
			else
				return type.formatType(suffix ~ "[]");
		}
		else if (name == ASSOC_ARRAY_SYMBOL_NAME)
		{
			// TODO: include AA key type
			if (!type)
				return suffix ~ "[...]";
			else
				return type.formatType(suffix ~ "[...]");
		}
		else
		{
			// TODO: include template parameters
			return name ~ suffix;
		}
	}
}

/**
 * istring with actual content and information if it was ditto
 */
struct DocString
{
	/// Creates a non-ditto comment.
	this(istring content)
	{
		this.rawContent = content;
	}

	/// Creates a comment which may have been ditto, but has been resolved.
	this(istring content, bool ditto)
	{
		this.rawContent = content;
		this.ditto = ditto;
	}

	alias toString this;

	deprecated("use toString to get a full formatted doc string or rawContent for just what is applied directly (or ditto'd) on the function") alias content = rawContent;

	/// Contains the documentation string associated with this symbol, resolves ditto to the previous comment with correct scope.
	istring rawContent;
	/// `true` if the documentation was just a "ditto" comment copying from the previous comment.
	bool ditto;
	/// Contains the source code + docstring for each documented unittest example associated with this symbol.
	istring[] examples;

	// package-private because we don't want to overcomplicate the lifetime in
	// the public API. (This might point to a broken address later)
	package(dsymbol) DocString* dittoOf;

	string toString() const @safe pure
	{
		import std.algorithm;
		import std.array;

		return examples.length
			? (rawContent ~ "\n\n" ~ examples.map!"a.data".join("\n"))
			: rawContent;
	}
}

struct UpdatePair
{
	ptrdiff_t opCmp(ref const UpdatePair other) const pure nothrow @nogc @safe
	{
		return (cast(ptrdiff_t) other.oldSymbol) - (cast(ptrdiff_t) this.oldSymbol);
	}

	DSymbol* oldSymbol;
	DSymbol* newSymbol;
}

alias UpdatePairCollectionAllocator = Mallocator;
alias UpdatePairCollection = TTree!(UpdatePair, UpdatePairCollectionAllocator, false, "a < b");

void generateUpdatePairs(DSymbol* oldSymbol, DSymbol* newSymbol, ref UpdatePairCollection results)
{
	results.insert(UpdatePair(oldSymbol, newSymbol));
	foreach (part; oldSymbol.parts[])
	{
		auto temp = DSymbol(oldSymbol.name);
		auto r = newSymbol.parts.equalRange(SymbolOwnership(&temp));
		if (r.empty)
			continue;
		generateUpdatePairs(part, r.front, results);
	}
}

struct SymbolOwnership
{
	ptrdiff_t opCmp(ref const SymbolOwnership other) const @nogc
	{
		return this.ptr.opCmp(*other.ptr);
	}

	DSymbol* ptr;
	bool owned;
	alias ptr this;
}
