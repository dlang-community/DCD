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

module dsymbol.scope_;

import dsymbol.symbol;
import dsymbol.import_;
import dsymbol.builtin.names;
import containers.ttree;
import containers.unrolledlist;
import std.algorithm : canFind, any;
import std.experimental.logger;
import std.experimental.allocator.gc_allocator : GCAllocator;

/**
 * Contains symbols and supports lookup of symbols by cursor position.
 */
struct Scope
{
	@disable this(this);
	@disable this();

	/**
	 * Params:
	 *     begin = the beginning byte index
	 *     end = the ending byte index
	 */
	this (uint begin, uint end)
	{
		this.startLocation = begin;
		this.endLocation = end;
	}

	~this()
	{
		foreach (child; children[])
			typeid(Scope).destroy(child);
		foreach (symbol; _symbols)
		{
			if (symbol.owned)
				typeid(DSymbol).destroy(symbol.ptr);
		}
	}

	/**
	 * Params:
	 *     cursorPosition = the cursor position in bytes
	 * Returns:
	 *     the innermost scope that contains the given cursor position
	 */
	Scope* getScopeByCursor(size_t cursorPosition) return pure @nogc
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
	DSymbol*[] getSymbolsInCursorScope(size_t cursorPosition)
	{
		import std.array : array;
		import std.algorithm.iteration : map;

		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return null;

		UnrolledList!(DSymbol*) retVal;
		Scope* sc = s;
		while (sc !is null)
		{
			foreach (item; sc._symbols[])
			{
				if (item.ptr.kind == CompletionKind.withSymbol)
				{
					if (item.ptr.type !is null)
						foreach (i; item.ptr.type.opSlice())
							retVal.insert(i);
				}
				else if (item.ptr.type !is null && item.ptr.kind == CompletionKind.importSymbol)
				{
					if (item.ptr.qualifier != SymbolQualifier.selectiveImport)
					{
						foreach (i; item.ptr.type.opSlice())
							retVal.insert(i);
					}
					else
						retVal.insert(item.ptr.type);
				}
				else
					retVal.insert(item.ptr);
			}
			sc = sc.parent;
		}
		return array(retVal[]);
	}

	/**
	 * Params:
	 *     name = the symbol name to search for
	 * Returns:
	 *     all symbols in this scope or parent scopes with the given name
	 */
	inout(DSymbol)*[] getSymbolsByName(istring name) inout
	{
		import std.array : array, appender;
		import std.algorithm.iteration : map;

		DSymbol s = DSymbol(name);
		auto er = _symbols.equalRange(SymbolOwnership(&s));
		if (!er.empty)
			return cast(typeof(return)) array(er.map!(a => a.ptr));

		// Check symbols from "with" statement
		DSymbol ir2 = DSymbol(WITH_SYMBOL_NAME);
		auto r2 = _symbols.equalRange(SymbolOwnership(&ir2));
		if (!r2.empty)
		{
			auto app = appender!(DSymbol*[])();
			foreach (e; r2)
			{
				if (e.type is null)
					continue;
				foreach (withSymbol; e.type.getPartsByName(s.name))
					app.put(cast(DSymbol*) withSymbol);
			}
			if (app.data.length > 0)
				return cast(typeof(return)) app.data;
		}

		if (name != CONSTRUCTOR_SYMBOL_NAME &&
			name != DESTRUCTOR_SYMBOL_NAME &&
			name != UNITTEST_SYMBOL_NAME &&
			name != THIS_SYMBOL_NAME)
		{
			// Check imported symbols
			DSymbol ir = DSymbol(IMPORT_SYMBOL_NAME);

			auto app = appender!(DSymbol*[])();
			foreach (e; _symbols.equalRange(SymbolOwnership(&ir)))
			{
				if (e.type is null)
					continue;
				if (e.qualifier == SymbolQualifier.selectiveImport && e.type.name == name)
					app.put(cast(DSymbol*) e.type);
				else
					foreach (importedSymbol; e.type.getPartsByName(s.name))
						app.put(cast(DSymbol*) importedSymbol);
			}
			if (app.data.length > 0)
				return cast(typeof(return)) app.data;
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
	DSymbol*[] getSymbolsByNameAndCursor(istring name, size_t cursorPosition)
	{
		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		return s.getSymbolsByName(name);
	}

	DSymbol* getFirstSymbolByNameAndCursor(istring name, size_t cursorPosition)
	{
		auto s = getSymbolsByNameAndCursor(name, cursorPosition);
		return s.length > 0 ? s[0] : null;
	}

	/**
	 * Returns an array of symbols that are present at global scope
	 */
	inout(DSymbol)*[] getSymbolsAtGlobalScope(istring name) inout
	{
		if (parent !is null)
			return parent.getSymbolsAtGlobalScope(name);
		return getSymbolsByName(name);
	}

	bool hasSymbolRecursive(const(DSymbol)* symbol) const
	{
		return _symbols[].canFind!(a => a == symbol) || children[].any!(a => a.hasSymbolRecursive(symbol));
	}

	/// The scope that contains this one
	Scope* parent;

	/// Child scopes
	alias ChildrenAllocator = GCAllocator; // NOTE using `Mallocator` here fails when analysing Phobos
	alias Children = UnrolledList!(Scope*, ChildrenAllocator);
	Children children;

	/// Start location of this scope in bytes
	uint startLocation;

	/// End location of this scope in bytes
	uint endLocation;

	auto symbols() @property
	{
		return _symbols[];
	}

	/**
	 * Adds the given symbol to this scope.
	 * Params:
	 *     symbol = the symbol to add
	 *     owns = if true, the symbol's destructor will be called when this
	 *         scope's destructor is called.
	 */
	void addSymbol(DSymbol* symbol, bool owns)
	{
		assert(symbol !is null);
		_symbols.insert(SymbolOwnership(symbol, owns));
	}

private:
	/// Symbols contained in this scope
	TTree!(SymbolOwnership, GCAllocator, true, "a.opCmp(b) < 0") _symbols; // NOTE using `Mallocator` here fails when analysing Phobos
}
