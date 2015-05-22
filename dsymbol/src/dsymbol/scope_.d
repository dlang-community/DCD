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
	DSymbol*[] getSymbolsInCursorScope(size_t cursorPosition) const
	{
		import std.array : array;

		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		UnrolledList!(DSymbol*) symbols;
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
	DSymbol*[] getSymbolsByName(istring name) const
	{
		import std.array : array, appender;

		DSymbol s = DSymbol(name);
		auto er = symbols.equalRange(&s);
		if (!er.empty)
			return array(er);

		// Check symbols from "with" statement
		DSymbol ir2 = DSymbol(WITH_SYMBOL_NAME);
		auto r2 = symbols.equalRange(&ir2);
		if (!r2.empty)
		{
			auto app = appender!(DSymbol*[])();
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
		DSymbol ir = DSymbol(IMPORT_SYMBOL_NAME);
		auto r = symbols.equalRange(&ir);
		if (!r.empty)
		{
			auto app = appender!(DSymbol*[])();
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
	DSymbol*[] getSymbolsByNameAndCursor(istring name, size_t cursorPosition) const
	{
		auto s = getScopeByCursor(cursorPosition);
		if (s is null)
			return [];
		return s.getSymbolsByName(name);
	}

	/**
	 * Returns an array of symbols that are present at global scope
	 */
	DSymbol*[] getSymbolsAtGlobalScope(istring name) const
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
	TTree!(DSymbol*, true, "a < b", false) symbols;
}
