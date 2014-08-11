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
		// Look for a parent scope whose start location equals this scope's
		// start location. This only happens in the case of functions with
		// contracts. Use this outer scope that covers the in, out, and body
		// instead of the smaller scope found by getScopeByCursor.
		if (s.parent !is null && s.parent.startLocation == s.startLocation)
			s = s.parent;
		if (currentSymbol.kind != CompletionKind.moduleName)
			s.symbols.insert(currentSymbol);
		foreach (part; currentSymbol.parts[])
		{
			if (part.kind != CompletionKind.keyword)
				assignToScopes(part);
		}
	}

	ACSymbol* createImportSymbols(ImportInformation* info, Scope* currentScope,
		ACSymbol*[] moduleSymbols)
	in
	{
		assert (info !is null);
		foreach (s; moduleSymbols)
			assert (s !is null);
	}
	body
	{
		immutable string firstPart = info.importParts[].front;
//		Log.trace("firstPart = ", firstPart);
		ACSymbol*[] symbols = currentScope.getSymbolsByName(firstPart);
		immutable bool found = symbols.length > 0;
		ACSymbol* firstSymbol = found
			? symbols[0] : allocate!ACSymbol(symbolAllocator, firstPart,
				CompletionKind.packageName);
		if (!found)
			currentScope.symbols.insert(firstSymbol);
//		Log.trace(firstSymbol.name);
		ACSymbol* currentSymbol = firstSymbol;
		size_t i = 0;
		foreach (string importPart; info.importParts[])
		{
			if (i++ == 0)
				continue;
			symbols = currentSymbol.getPartsByName(importPart);
			ACSymbol* s = symbols.length > 0
				? cast(ACSymbol*) symbols[0] : allocate!ACSymbol(symbolAllocator,
					importPart, CompletionKind.packageName);
			currentSymbol.parts.insert(s);
			currentSymbol = s;
		}
		currentSymbol.kind = CompletionKind.moduleName;
		currentSymbol.parts.insert(moduleSymbols);
//		Log.trace(currentSymbol.name);
		return currentSymbol;
	}

	void resolveImports(Scope* currentScope)
	{
		import modulecache;
		import std.stdio;
		foreach (importInfo; currentScope.importInformation[])
		{
			string location = ModuleCache.resolveImportLoctation(importInfo.modulePath);
			ACSymbol*[] symbols = location is null ? [] : ModuleCache.getSymbolsInModule(location);
			ACSymbol* moduleSymbol = createImportSymbols(importInfo, currentScope, symbols);
			currentScope.symbols.insert(moduleSymbol);
			currentScope.symbols.insert(symbols);
			if (importInfo.importedSymbols.length == 0)
			{
				if (importInfo.isPublic && currentScope.parent is null)
				{
					rootSymbol.acSymbol.parts.insert(symbols);
				}
				continue;
			}
			symbolLoop: foreach (symbol; symbols)
			{
				foreach (tup; importInfo.importedSymbols[])
				{
					if (tup[0] != symbol.name)
						continue symbolLoop;
					if (tup[1] !is null)
					{
						ACSymbol* s = allocate!ACSymbol(symbolAllocator, tup[1],
							symbol.kind, symbol.type);
						// TODO: Compiler gets confused here, so cast the types.
						s.parts.insert(symbol.parts[]);
						// TODO: Re-format callTip with new name?
						s.callTip = symbol.callTip;
						s.doc = symbol.doc;
						s.qualifier = symbol.qualifier;
						s.location = symbol.location;
						s.symbolFile = symbol.symbolFile;
						currentScope.symbols.insert(s);
						moduleSymbol.parts.insert(s);
						if (importInfo.isPublic && currentScope.parent is null)
							rootSymbol.acSymbol.parts.insert(s);
					}
					else
					{
						moduleSymbol.parts.insert(symbol);
						currentScope.symbols.insert(symbol);
						if (importInfo.isPublic && currentScope.parent is null)
							rootSymbol.acSymbol.parts.insert(symbol);
					}
				}
			}
		}
		foreach (childScope; currentScope.children)
			resolveImports(childScope);
	}
}
