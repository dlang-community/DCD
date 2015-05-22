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

module dsymbol.conversion.second;

import dsymbol.conversion.first;
import dsymbol.semantic;
import dsymbol.string_interning;
import dsymbol.symbol;
import dsymbol.scope_;
import dsymbol.import_;
import dsymbol.builtin.symbols;
import dsymbol.builtin.names;
import std.allocator;

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
		assignToScopes(rootSymbol.acSymbol);
		moduleScope.symbols.insert(builtinSymbols[]);
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
	void assignToScopes(DSymbol* currentSymbol)
	{
		if (currentSymbol.kind != CompletionKind.moduleName)
		{
			Scope* s = moduleScope.getScopeByCursor(currentSymbol.location);
			s.symbols.insert(currentSymbol);
		}
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
	DSymbol* createImportSymbols(ImportInformation* info, Scope* currentScope,
		DSymbol* moduleSymbol)
	in
	{
		assert (info !is null);
		assert (currentScope !is null);
		assert (moduleSymbol !is null);
	}
	body
	{
		// top-level package name
		immutable istring firstPart = info.importParts[].front;

		// top-level package symbol
		DSymbol* firstSymbol = void;
		DSymbol*[] symbols = currentScope.getSymbolsByName(firstPart);
		if (symbols.length > 0)
			firstSymbol = symbols[0];
		else
			firstSymbol = allocate!DSymbol(symbolAllocator, firstPart,
				CompletionKind.packageName);
		DSymbol* currentSymbol = firstSymbol;
		size_t i = 0;
		foreach (importPart; info.importParts[])
		{
			i++;
			if (i == 1) // Skip the top-level package
				continue;
			if (i + 2 >= info.importParts.length) // Skip the last item as it's the module name
				break;
			symbols = currentSymbol.getPartsByName(importPart);
			DSymbol* s = null;
			foreach (sy; symbols)
			{
				if (sy.kind == CompletionKind.packageName)
				{
					s = sy;
					break;
				}
			}
			if (s is null)
				s = allocate!DSymbol(symbolAllocator, importPart, CompletionKind.packageName);
			currentSymbol.parts.insert(s);
			currentSymbol = s;
		}
		currentSymbol.parts.insert(moduleSymbol);
		return currentSymbol;
	}

	/**
	 * Creates or adds symbols to the given scope based off of the import
	 * statements contained therein.
	 */
	void resolveImports(Scope* currentScope)
	{
		import dsymbol.modulecache : ModuleCache;
		foreach (importInfo; currentScope.importInformation[])
		{
			// Get symbol for the imported module
			immutable string moduleAbsPath = ModuleCache.resolveImportLoctation(
				importInfo.modulePath);
			DSymbol* symbol = moduleAbsPath is null ? null
				: ModuleCache.getModuleSymbol(moduleAbsPath);
			if (symbol is null)
				continue;

			DSymbol* moduleSymbol = createImportSymbols(importInfo, currentScope, symbol);

			// if this is a selective import
			if (importInfo.importedSymbols.length == 0)
			{
				// if this import is at module scope
				if (importInfo.isPublic && currentScope.parent is null)
					rootSymbol.acSymbol.parts.insert(allocate!DSymbol(symbolAllocator,
						IMPORT_SYMBOL_NAME, CompletionKind.importSymbol, symbol));
				else
					currentScope.symbols.insert(symbol.parts[]);
				currentScope.symbols.insert(moduleSymbol);
				continue;
			}
			else foreach (tup; importInfo.importedSymbols[])
			{
				// Handle selective and renamed imports

				DSymbol needle = DSymbol(tup[1]);
				DSymbol* sym;
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
				if (tup[0] !is null)
				{
					DSymbol* s = allocate!DSymbol(symbolAllocator, tup[0],
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

		// Recurse to child scopes
		foreach (childScope; currentScope.children)
			resolveImports(childScope);
	}
}
