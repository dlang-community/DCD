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

	this(FirstPass first)
	{
		this.rootSymbol = first.rootSymbol;
		this.moduleScope = first.moduleScope;
		this.symbolAllocator = first.symbolAllocator;
	}

	void run()
	{
		rootSymbol.acSymbol.parts.insert(builtinSymbols[]);
		assignToScopes(rootSymbol.acSymbol);
		resolveImports(moduleScope);
	}

	CAllocator symbolAllocator;
	SemanticSymbol* rootSymbol;
	Scope* moduleScope;

private:

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
	 */
	ACSymbol* createImportSymbols(ImportInformation* info, Scope* currentScope,
		ACSymbol* moduleSymbol)
	in
	{
		assert (info !is null);
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
		currentScope.symbols.insert(firstSymbol);
		ACSymbol* currentSymbol = firstSymbol;
		size_t i = 0;
		foreach (string importPart; info.importParts[])
		{
			if (i++ == 0)
				continue;
			if (i + 2 >= info.importParts.length) // Skip the last item as it's the module name
				break;
			symbols = currentSymbol.getPartsByName(importPart);
			ACSymbol* s = symbols.length > 0
				? cast(ACSymbol*) symbols[0] : allocate!ACSymbol(symbolAllocator,
					importPart, CompletionKind.packageName);
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
			currentScope.symbols.insert(symbol.parts[]);
			if (importInfo.importedSymbols.length == 0)
			{
				if (importInfo.isPublic && currentScope.parent is null)
				{
					rootSymbol.acSymbol.parts.insert(allocate!ACSymbol(symbolAllocator,
						IMPORT_SYMBOL_NAME, CompletionKind.importSymbol, symbol));
				}
				continue;
			}
			symbolLoop: foreach (sym; symbol.parts[])
			{
				foreach (tup; importInfo.importedSymbols[])
				{
					if (tup[0] != symbol.name)
						continue symbolLoop;
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
						currentScope.symbols.insert(s);
						moduleSymbol.parts.insert(s);
						if (importInfo.isPublic && currentScope.parent is null)
							rootSymbol.acSymbol.parts.insert(s);
					}
					else
					{
						moduleSymbol.parts.insert(sym);
						currentScope.symbols.insert(sym);
						if (importInfo.isPublic && currentScope.parent is null)
							rootSymbol.acSymbol.parts.insert(sym);
					}
				}
			}
		}
		foreach (childScope; currentScope.children)
			resolveImports(childScope);
	}
}
