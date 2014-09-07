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

module conversion.second;

import conversion.first;
import actypes;
import semantic;
import messages;
import std.allocator;
import stupidlog;
import string_interning;

/**
 * Second pass handles the following:
 * $(UL
 *     $(LI Import statements)
 *     $(LI assigning symbols to scopes)
 * )
 */
struct SecondPass
{
public:

	/**
	 * Construct this with the results of the first pass
	 * Params:
	 *     first = the first pass
	 */
	this(FirstPass first)
	{
		this.rootSymbol = first.rootSymbol;
		this.moduleScope = first.moduleScope;
		this.symbolAllocator = first.symbolAllocator;
	}

	/**
	 * Runs the second pass on the module.
	 */
	void run()
	{
		rootSymbol.acSymbol.parts.insert(builtinSymbols[]);
		assignToScopes(rootSymbol.acSymbol);
		resolveImports(moduleScope);
	}

	/**
	 * Allocator used for allocating autocomplete symbols.
	 */
	CAllocator symbolAllocator;

	/**
	 * The root symbol from the first pass
	 */
	SemanticSymbol* rootSymbol;

	/**
	 * The module scope from the first pass
	 */
	Scope* moduleScope;

private:

	/**
	 * Assigns symbols to scopes based on their location.
	 */
	void assignToScopes(ACSymbol* currentSymbol)
	{
		Scope* s = moduleScope.getScopeByCursor(currentSymbol.location);
		if (currentSymbol.kind != CompletionKind.moduleName)
			s.symbols.insert(currentSymbol);
		foreach (part; currentSymbol.parts[])
		{
			if (part.kind != CompletionKind.keyword)
				assignToScopes(part);
		}
	}

	/**
	 * Creates package symbols as necessary to contain the given module symbol
	 * Params:
	 *     info = the import information for the module being imported
	 *     currentScope = the scope in which the import statement is located
	 *     moduleSymbol = the module being imported
	 * Returns: A package symbol that can be used for auto-completing qualified
	 * symbol names.
	 */
	ACSymbol* createImportSymbols(ImportInformation* info, Scope* currentScope,
		ACSymbol* moduleSymbol)
	in
	{
		assert (info !is null);
		assert (currentScope !is null);
		assert (moduleSymbol !is null);
	}
	body
	{
		immutable string firstPart = info.importParts[].front;
		ACSymbol*[] symbols = currentScope.getSymbolsByName(firstPart);
		ACSymbol* firstSymbol = void;
		if (symbols.length > 0)
			firstSymbol = symbols[0];
		else
			firstSymbol = allocate!ACSymbol(symbolAllocator, firstPart,
				CompletionKind.packageName);
		ACSymbol* currentSymbol = firstSymbol;
		size_t i = 0;
		foreach (string importPart; info.importParts[])
		{
			if (i++ == 0)
				continue;
			if (i + 2 >= info.importParts.length) // Skip the last item as it's the module name
				break;
			symbols = currentSymbol.getPartsByName(importPart);
			ACSymbol* s = null;
			if (symbols.length > 0) foreach (sy; symbols)
			{
				if (sy.kind == CompletionKind.packageName)
				{
					s = sy;
					break;
				}
			}
			if (s is null)
				s = allocate!ACSymbol(symbolAllocator, importPart, CompletionKind.packageName);
			currentSymbol.parts.insert(s);
			currentSymbol = s;
		}
		currentSymbol.parts.insert(moduleSymbol);
		return currentSymbol;
	}

	void resolveImports(Scope* currentScope)
	{
		import modulecache;
		import std.stdio;
		foreach (importInfo; currentScope.importInformation[])
		{
			string location = ModuleCache.resolveImportLoctation(importInfo.modulePath);
			ACSymbol* symbol = location is null ? null : ModuleCache.getSymbolsInModule(location);
			if (symbol is null)
				continue;
			ACSymbol* moduleSymbol = createImportSymbols(importInfo, currentScope, symbol);
			if (importInfo.importedSymbols.length == 0)
			{
				if (importInfo.isPublic && currentScope.parent is null)
					rootSymbol.acSymbol.parts.insert(allocate!ACSymbol(symbolAllocator,
						IMPORT_SYMBOL_NAME, CompletionKind.importSymbol, symbol));
				else
					currentScope.symbols.insert(symbol.parts[]);
				currentScope.symbols.insert(moduleSymbol);
				continue;
			}

			foreach (tup; importInfo.importedSymbols[])
			{
				ACSymbol needle = ACSymbol(tup[0]);
				ACSymbol* sym;
				auto r = symbol.parts.equalRange(&needle);
				if (r.empty) foreach (sy; symbol.parts[])
				{
					if (sy.kind != CompletionKind.importSymbol || sy.type is null)
						continue;
					auto ra = sy.type.parts.equalRange(&needle);
					if (ra.empty)
						continue;
					sym = ra.front;
				}
				else
					sym = r.front;
				if (sym is null)
					continue;
				if (tup[1] !is null)
				{
					ACSymbol* s = allocate!ACSymbol(symbolAllocator, tup[1],
						sym.kind, sym.type);
					s.parts.insert(sym.parts[]);
					s.callTip = sym.callTip;
					s.doc = sym.doc;
					s.qualifier = sym.qualifier;
					s.location = sym.location;
					s.symbolFile = sym.symbolFile;
					sym = s;
				}
				moduleSymbol.parts.insert(sym);
				currentScope.symbols.insert(sym);
				if (importInfo.isPublic && currentScope.parent is null)
					rootSymbol.acSymbol.parts.insert(sym);
			}
		}
		foreach (childScope; currentScope.children)
			resolveImports(childScope);
	}
}
