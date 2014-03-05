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
import stdx.lexer : StringCache;

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

	this(ref FirstPass first)
	{
		this.rootSymbol = first.rootSymbol;
		this.moduleScope = first.moduleScope;
		this.stringCache = first.stringCache;
	}

	void run()
	{
		assignToScopes(rootSymbol.acSymbol);
		resolveImports(moduleScope);
	}

	SemanticSymbol* rootSymbol;
	Scope* moduleScope;
	shared(StringCache)* stringCache;

private:

	void assignToScopes(ACSymbol* currentSymbol)
	{
		Scope* s = moduleScope.getScopeByCursor(currentSymbol.location);
		s.symbols.insert(currentSymbol);
		foreach (part; currentSymbol.parts[])
			assignToScopes(part);
	}

	// This method is really ugly due to the casts...
	static ACSymbol* createImportSymbols(ImportInformation info,
		Scope* currentScope, ACSymbol*[] moduleSymbols)
	{
		immutable string firstPart = info.importParts[0];
		ACSymbol*[] symbols = currentScope.getSymbolsByName(firstPart);
		immutable bool found = symbols.length > 0;
		ACSymbol* firstSymbol = found
			? symbols[0] : new ACSymbol(firstPart, CompletionKind.packageName);
		if (!found)
		{
			currentScope.symbols.insert(firstSymbol);
		}
		ACSymbol* currentSymbol = cast(ACSymbol*) firstSymbol;
		foreach (size_t i, string importPart; info.importParts[1 .. $])
		{
			symbols = currentSymbol.getPartsByName(importPart);
			ACSymbol* s = symbols.length > 0
				? cast(ACSymbol*) symbols[0] : new ACSymbol(importPart, CompletionKind.packageName);
			currentSymbol.parts.insert(s);
			currentSymbol = s;
		}
		currentSymbol.kind = CompletionKind.moduleName;
		currentSymbol.parts.insert(moduleSymbols);
		return currentSymbol;
	}

	void resolveImports(Scope* currentScope)
	{
		import modulecache;
		foreach (importInfo; currentScope.importInformation)
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
				foreach (tup; importInfo.importedSymbols)
				{
					if (tup[0] != symbol.name)
						continue symbolLoop;
					if (tup[1] !is null)
					{
						ACSymbol* s = new ACSymbol(tup[1],
							symbol.kind, symbol.type);
						// TODO: Compiler gets confused here, so cast the types.
						s.parts = cast(typeof(s.parts)) symbol.parts;
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
