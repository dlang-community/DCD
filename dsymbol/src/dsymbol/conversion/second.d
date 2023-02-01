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

import dsymbol.semantic;
import dsymbol.string_interning;
import dsymbol.symbol;
import dsymbol.scope_;
import dsymbol.builtin.names;
import dsymbol.builtin.symbols;
import dsymbol.type_lookup;
import dsymbol.deferred;
import dsymbol.import_;
import dsymbol.modulecache;
import std.experimental.allocator;
import std.experimental.allocator.gc_allocator : GCAllocator;
import std.experimental.logger;
import dparse.ast;
import dparse.lexer;

void secondPass(SemanticSymbol* currentSymbol, Scope* moduleScope, ref ModuleCache cache)
{
	with (CompletionKind) final switch (currentSymbol.acSymbol.kind)
	{
	case className:
	case interfaceName:
		resolveInheritance(currentSymbol.acSymbol, currentSymbol.typeLookups,
			moduleScope, cache);
		break;
	case withSymbol:
	case variableName:
	case memberVariableName:
	case functionName:
	case ufcsName:
	case aliasName:
		// type may not be null in the case of a renamed import
		if (currentSymbol.acSymbol.type is null)
		{
			resolveType(currentSymbol.acSymbol, currentSymbol.typeLookups,
				moduleScope, cache);
		}
		break;
	case importSymbol:
		if (currentSymbol.acSymbol.type is null)
			resolveImport(currentSymbol.acSymbol, currentSymbol.typeLookups, cache);
		break;
	case variadicTmpParam:
		currentSymbol.acSymbol.type = variadicTmpParamSymbol;
		break;
	case typeTmpParam:
		currentSymbol.acSymbol.type = typeTmpParamSymbol;
		break;
	case structName:
	case unionName:
	case enumName:
	case keyword:
	case enumMember:
	case packageName:
	case moduleName:
	case dummy:
	case templateName:
	case mixinTemplateName:
		break;
	}

	foreach (child; currentSymbol.children)
		secondPass(child, moduleScope, cache);

	// Alias this and mixin templates are resolved after child nodes are
	// resolved so that the correct symbol information will be available.
	with (CompletionKind) switch (currentSymbol.acSymbol.kind)
	{
	case className:
	case interfaceName:
	case structName:
	case unionName:
		resolveAliasThis(currentSymbol.acSymbol, currentSymbol.typeLookups, moduleScope, cache);
		resolveMixinTemplates(currentSymbol.acSymbol, currentSymbol.typeLookups,
			moduleScope, cache);
		break;
	default:
		break;
	}
}

void resolveImport(DSymbol* acSymbol, ref TypeLookups typeLookups,
	ref ModuleCache cache)
in
{
	assert(acSymbol.kind == CompletionKind.importSymbol);
	assert(acSymbol.symbolFile !is null);
}
do
{
	DSymbol* moduleSymbol = cache.cacheModule(acSymbol.symbolFile);
	if (acSymbol.qualifier == SymbolQualifier.selectiveImport)
	{
		if (moduleSymbol is null)
		{
		tryAgain:
			DeferredSymbol* deferred = DeferredSymbolsAllocator.instance.make!DeferredSymbol(acSymbol);
			deferred.typeLookups.insert(typeLookups[]);
			// Get rid of the old references to the lookups, this new deferred
			// symbol owns them now
			typeLookups.clear();
			cache.deferredSymbols.insert(deferred);
		}
		else
		{
			immutable size_t breadcrumbCount = typeLookups.front.breadcrumbs.length;
			assert(breadcrumbCount <= 2 && breadcrumbCount > 0, "Malformed selective import");

			istring symbolName = typeLookups.front.breadcrumbs.front;
			DSymbol* selected = moduleSymbol.getFirstPartNamed(symbolName);
			if (selected is null)
				goto tryAgain;
			acSymbol.type = selected;
			acSymbol.ownType = false;

			// count of 1 means selective import
			// count of 2 means a renamed selective import
			if (breadcrumbCount == 2)
			{
				acSymbol.kind = CompletionKind.aliasName;
				acSymbol.symbolFile = acSymbol.altFile;
			}
		}
	}
	else
	{
		if (moduleSymbol is null)
		{
			DeferredSymbol* deferred = DeferredSymbolsAllocator.instance.make!DeferredSymbol(acSymbol);
			cache.deferredSymbols.insert(deferred);
		}
		else
		{
			acSymbol.type = moduleSymbol;
			acSymbol.ownType = false;
		}
	}
}

void resolveTypeFromType(DSymbol* symbol, TypeLookup* lookup, Scope* moduleScope,
	ref ModuleCache cache, Imports* imports)
in
{
	if (imports !is null)
		foreach (i; imports.opSlice())
			assert(i.kind == CompletionKind.importSymbol);
}
do
{
	// The left-most suffix
	DSymbol* suffix;
	// The right-most suffix
	DSymbol* lastSuffix;

	// Create symbols for the type suffixes such as array and
	// associative array
	while (!lookup.breadcrumbs.empty)
	{
		auto back = lookup.breadcrumbs.back;
		immutable bool isArr = back == ARRAY_SYMBOL_NAME;
		immutable bool isAssoc = back == ASSOC_ARRAY_SYMBOL_NAME;
		immutable bool isFunction = back == FUNCTION_SYMBOL_NAME;
		if (back == POINTER_SYMBOL_NAME)
		{
			lastSuffix.isPointer = true;
			lookup.breadcrumbs.popBack();
			continue;
		}
		if (!isArr && !isAssoc && !isFunction)
			break;
		immutable qualifier = isAssoc ? SymbolQualifier.assocArray :
			(isFunction ? SymbolQualifier.func : SymbolQualifier.array);
		lastSuffix = GCAllocator.instance.make!DSymbol(back, CompletionKind.dummy, lastSuffix);
		lastSuffix.qualifier = qualifier;
		lastSuffix.ownType = true;
		if (isFunction)
		{
			lookup.breadcrumbs.popBack();
			lastSuffix.callTip = lookup.breadcrumbs.back();
		}
		else
			lastSuffix.addChildren(isArr ? arraySymbols[] : assocArraySymbols[], false);

		if (suffix is null)
			suffix = lastSuffix;
		lookup.breadcrumbs.popBack();
	}

	Imports remainingImports;

	DSymbol* currentSymbol;

	void getSymbolFromImports(Imports* importList, istring name)
	{
		foreach (im; importList.opSlice())
		{
			assert(im.symbolFile !is null);
			// Try to find a cached version of the module
			DSymbol* moduleSymbol = cache.getModuleSymbol(im.symbolFile);
			// If the module has not been cached yet, store it in the
			// remaining imports list
			if (moduleSymbol is null)
			{
				remainingImports.insert(im);
				continue;
			}
			// Try to get the symbol from the imported module
			currentSymbol = moduleSymbol.getFirstPartNamed(name);
			if (currentSymbol is null)
				continue;
		}
	}

	// Follow all the names and try to resolve them
	size_t i = 0;
	foreach (part; lookup.breadcrumbs[])
	{
		if (i == 0)
		{
			if (moduleScope is null)
				getSymbolFromImports(imports, part);
			else
			{
				auto symbols = moduleScope.getSymbolsByNameAndCursor(part, symbol.location);
				if (symbols.length > 0)
					currentSymbol = symbols[0];
				else
				{
					// store the callTip, that'll be useful to resolve the type later
					symbol.callTip = istring(part);
					return;
				}
			}
		}
		else
		{
			if (currentSymbol.kind == CompletionKind.aliasName)
				currentSymbol = currentSymbol.type;
			if (currentSymbol is null)
				return;
			if (currentSymbol.kind == CompletionKind.moduleName && currentSymbol.type !is null)
				currentSymbol = currentSymbol.type;
			if (currentSymbol is null)
				return;
			if (currentSymbol.kind == CompletionKind.importSymbol)
				currentSymbol = currentSymbol.type;
			if (currentSymbol is null)
				return;
			currentSymbol = currentSymbol.getFirstPartNamed(part);
		}
		++i;
		if (currentSymbol is null)
			return;
	}

	if (lastSuffix !is null)
	{
		assert(suffix !is null);
		suffix.type = currentSymbol;
		suffix.ownType = false;
		symbol.type = lastSuffix;
		symbol.ownType = true;
		if (currentSymbol is null && !remainingImports.empty)
		{
//			info("Deferring type resolution for ", symbol.name);
			auto deferred = DeferredSymbolsAllocator.instance.make!DeferredSymbol(suffix);
			// TODO: The scope has ownership of the import information
			deferred.imports.insert(remainingImports[]);
			deferred.typeLookups.insert(lookup);
			cache.deferredSymbols.insert(deferred);
		}
	}
	else if (currentSymbol !is null)
	{
		symbol.type = currentSymbol;
		symbol.ownType = false;
	}
	else if (!remainingImports.empty)
	{
		auto deferred = DeferredSymbolsAllocator.instance.make!DeferredSymbol(symbol);
//		info("Deferring type resolution for ", symbol.name);
		// TODO: The scope has ownership of the import information
		deferred.imports.insert(remainingImports[]);
		deferred.typeLookups.insert(lookup);
		cache.deferredSymbols.insert(deferred);
	}
}

private:

void resolveInheritance(DSymbol* symbol, ref TypeLookups typeLookups,
	Scope* moduleScope, ref ModuleCache cache)
{
	import std.algorithm : filter;

	outer: foreach (TypeLookup* lookup; typeLookups[])
	{
		if (lookup.kind != TypeLookupKind.inherit)
			continue;
		DSymbol* baseClass;
		assert(lookup.breadcrumbs.length > 0);

		// TODO: Delayed type lookup
		auto symbolScope = moduleScope.getScopeByCursor(
			symbol.location + symbol.name.length);
		auto symbols = moduleScope.getSymbolsByNameAndCursor(lookup.breadcrumbs.front,
			symbol.location);
		if (symbols.length == 0)
			continue;

		baseClass = symbols[0];
		lookup.breadcrumbs.popFront();
		foreach (part; lookup.breadcrumbs[])
		{
			symbols = baseClass.getPartsByName(part);
			if (symbols.length == 0)
				continue outer;
			baseClass = symbols[0];
		}

		DSymbol* imp = GCAllocator.instance.make!DSymbol(IMPORT_SYMBOL_NAME,
			CompletionKind.importSymbol, baseClass);
		symbol.addChild(imp, true);
		symbolScope.addSymbol(imp, false);
		if (baseClass.kind == CompletionKind.className)
		{
			auto s = GCAllocator.instance.make!DSymbol(SUPER_SYMBOL_NAME,
				CompletionKind.variableName, baseClass);
			symbolScope.addSymbol(s, true);
		}
	}
}

void resolveAliasThis(DSymbol* symbol,
	ref TypeLookups typeLookups, Scope* moduleScope, ref ModuleCache cache)
{
	import std.algorithm : filter;

	foreach (aliasThis; typeLookups[].filter!(a => a.kind == TypeLookupKind.aliasThis))
	{
		assert(aliasThis.breadcrumbs.length > 0);
		auto parts = symbol.getPartsByName(aliasThis.breadcrumbs.front);
		if (parts.length == 0 || parts[0].type is null)
			continue;
		DSymbol* s = GCAllocator.instance.make!DSymbol(IMPORT_SYMBOL_NAME,
			CompletionKind.importSymbol, parts[0].type);
		symbol.addChild(s, true);
		auto symbolScope = moduleScope.getScopeByCursor(s.location);
		if (symbolScope !is null)
			symbolScope.addSymbol(s, false);
	}
}

void resolveMixinTemplates(DSymbol* symbol,
	ref TypeLookups typeLookups, Scope* moduleScope, ref ModuleCache cache)
{
	import std.algorithm : filter;

	foreach (mix; typeLookups[].filter!(a => a.kind == TypeLookupKind.mixinTemplate))
	{
		assert(mix.breadcrumbs.length > 0);
		auto symbols = moduleScope.getSymbolsByNameAndCursor(mix.breadcrumbs.front,
			symbol.location);
		if (symbols.length == 0)
			continue;
		auto currentSymbol = symbols[0];
		mix.breadcrumbs.popFront();
		foreach (m; mix.breadcrumbs[])
		{
			auto s = currentSymbol.getPartsByName(m);
			if (s.length == 0)
			{
				currentSymbol = null;
				break;
			}
			else
				currentSymbol = s[0];
		}
		if (currentSymbol !is null)
		{
			auto i = GCAllocator.instance.make!DSymbol(IMPORT_SYMBOL_NAME,
				CompletionKind.importSymbol, currentSymbol);
			i.ownType = false;
			symbol.addChild(i, true);
		}
	}
}

void resolveType(DSymbol* symbol, ref TypeLookups typeLookups,
	Scope* moduleScope, ref ModuleCache cache)
{

	import std.conv;

	if (typeLookups.length == 0)
		return;
	assert(typeLookups.length == 1);
	auto lookup = typeLookups.front;
	if (lookup.kind == TypeLookupKind.varOrFunType)
		resolveTypeFromType(symbol, lookup, moduleScope, cache, null);
	else if (lookup.kind == TypeLookupKind.initializer)
		resolveTypeFromInitializer(symbol, lookup, moduleScope, cache);
	// issue 94
	else if (lookup.kind == TypeLookupKind.inherit)
		resolveInheritance(symbol, typeLookups, moduleScope, cache);
	else
		assert(false, "How did this happen?");
}


void resolveTypeFromInitializer(DSymbol* symbol, TypeLookup* lookup,
	Scope* moduleScope, ref ModuleCache cache)
{
	if (lookup.breadcrumbs.length == 0)
		return;
	DSymbol* currentSymbol = null;
	size_t i = 0;

	auto crumbs = lookup.breadcrumbs[];
	foreach (crumb; crumbs)
	{
		if (i == 0)
		{
			currentSymbol = moduleScope.getFirstSymbolByNameAndCursor(
				symbolNameToTypeName(crumb), symbol.location);

			if (currentSymbol is null)
				return;
		}
		else
		if (crumb == ARRAY_LITERAL_SYMBOL_NAME)
		{
			auto arr = GCAllocator.instance.make!(DSymbol)(ARRAY_LITERAL_SYMBOL_NAME, CompletionKind.dummy, currentSymbol);
			arr.qualifier = SymbolQualifier.array;
			currentSymbol = arr;
		}
		else if (crumb == ARRAY_SYMBOL_NAME)
		{
			typeSwap(currentSymbol);
			if (currentSymbol is null)
				return;

			// Index expressions can be an array index or an AA index
			if (currentSymbol.qualifier == SymbolQualifier.array
					|| currentSymbol.qualifier == SymbolQualifier.assocArray
					|| currentSymbol.kind == CompletionKind.aliasName)
			{
				if (currentSymbol.type !is null)
					currentSymbol = currentSymbol.type;
				else
					return;
			}
			else
			{
				auto opIndex = currentSymbol.getFirstPartNamed(internString("opIndex"));
				if (opIndex !is null)
					currentSymbol = opIndex.type;
				else
					return;
			}
		}
		else if (crumb == "foreach")
		{
			typeSwap(currentSymbol);
			if (currentSymbol is null)
				return;
			if (currentSymbol.qualifier == SymbolQualifier.array
					|| currentSymbol.qualifier == SymbolQualifier.assocArray)
			{
				currentSymbol = currentSymbol.type;
				break;
			}
			auto front = currentSymbol.getFirstPartNamed(internString("front"));
			if (front !is null)
			{
				currentSymbol = front.type;
				break;
			}
			auto opApply = currentSymbol.getFirstPartNamed(internString("opApply"));
			if (opApply !is null)
			{
				currentSymbol = opApply.type;
				break;
			}
		}
		else
		{
			typeSwap(currentSymbol);
			if (currentSymbol is null )
				return;
			currentSymbol = currentSymbol.getFirstPartNamed(crumb);
		}
		++i;
		if (currentSymbol is null)
			return;
	}
	typeSwap(currentSymbol);
	symbol.type = currentSymbol;
	symbol.ownType = false;
}

void typeSwap(ref DSymbol* currentSymbol)
{
	while (currentSymbol !is null && currentSymbol.type !is currentSymbol
			&& (currentSymbol.kind == CompletionKind.variableName
			|| currentSymbol.kind == CompletionKind.importSymbol
			|| currentSymbol.kind == CompletionKind.withSymbol
			|| currentSymbol.kind == CompletionKind.aliasName))
		currentSymbol = currentSymbol.type;
}
