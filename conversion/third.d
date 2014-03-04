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

module conversion.third;

import stdx.d.ast;
import stdx.d.lexer;
import conversion.second;
import semantic;
import actypes;
import messages;


/**
 * Third pass handles the following:
 * $(UL
 *      $(LI types)
 *      $(LI base classes)
 *      $(LI mixin templates)
 *      $(LI alias this)
 *      $(LI alias declarations)
 * )
 */
struct ThirdPass
{
public:
	this(ref SecondPass second, string name = "none") pure
	{
		this.rootSymbol = second.rootSymbol;
		this.moduleScope = second.moduleScope;
		this.stringCache = second.stringCache;
		this.name = name;
	}

	string name;

	void run()
	{
		thirdPass(rootSymbol);
	}

	SemanticSymbol* rootSymbol;
	Scope* moduleScope;

private:

	void thirdPass(SemanticSymbol* currentSymbol)
	{
//		Log.trace("third pass on ", currentSymbol.acSymbol.name);
		with (CompletionKind) final switch (currentSymbol.acSymbol.kind)
		{
		case className:
		case interfaceName:
			resolveInheritance(currentSymbol);
			goto case structName;
		case structName:
		case unionName:
			resolveAliasThis(currentSymbol);
			resolveMixinTemplates(currentSymbol);
			break;
		case variableName:
		case memberVariableName:
		case functionName:
		case aliasName:
			ACSymbol* t = resolveType(currentSymbol.type,
				currentSymbol.acSymbol.location);
			while (t !is null && t.kind == CompletionKind.aliasName)
				t = t.type;
			currentSymbol.acSymbol.type = t;
			break;
		case enumName:
		case keyword:
		case enumMember:
		case packageName:
		case moduleName:
		case dummy:
		case array:
		case assocArray:
		case templateName:
		case mixinTemplateName:
			break;
		}
		foreach (child; currentSymbol.children)
		{
			thirdPass(child);
		}
	}

	void resolveInheritance(SemanticSymbol* currentSymbol)
	{
//		Log.trace("Resolving inheritance for ", currentSymbol.acSymbol.name);
		outer: foreach (string[] base; currentSymbol.baseClasses)
		{
			ACSymbol* baseClass;
			if (base.length == 0)
				continue;
			auto symbols = moduleScope.getSymbolsByNameAndCursor(
				base[0], currentSymbol.acSymbol.location);
			if (symbols.length == 0)
				continue;
			baseClass = symbols[0];
			foreach (part; base[1..$])
			{
				symbols = baseClass.getPartsByName(part);
				if (symbols.length == 0)
					continue outer;
				baseClass = symbols[0];
			}
			currentSymbol.acSymbol.parts.insert(baseClass.parts[]);
		}
	}

	void resolveAliasThis(SemanticSymbol* currentSymbol)
	{
		// TODO:
	}

	void resolveMixinTemplates(SemanticSymbol* currentSymbol)
	{
		// TODO:
	}

	ACSymbol* resolveType(const Type t, size_t location)
	{
		if (t is null) return null;
		if (t.type2 is null) return null;
		ACSymbol* s;
		if (t.type2.builtinType != tok!"")
			s = convertBuiltinType(t.type2);
		else if (t.type2.typeConstructor != tok!"")
			s = resolveType(t.type2.type, location);
		else if (t.type2.symbol !is null)
		{
			// TODO: global scoped symbol handling
			string[] symbolParts = expandSymbol(
				t.type2.symbol.identifierOrTemplateChain, stringCache, name);
			auto symbols = moduleScope.getSymbolsByNameAndCursor(
				symbolParts[0], location);
			if (symbols.length == 0)
				goto resolveSuffixes;
			s = symbols[0];
			foreach (symbolPart; symbolParts[1..$])
			{
				auto parts = s.getPartsByName(symbolPart);
				if (parts.length == 0)
					goto resolveSuffixes;
				s = parts[0];
			}
		}
	resolveSuffixes:
		foreach (suffix; t.typeSuffixes)
			s = processSuffix(s, suffix);
		return s;
	}

	static string[] expandSymbol(const IdentifierOrTemplateChain chain,
		shared(StringCache)* stringCache, string n)
	{
		if (chain.identifiersOrTemplateInstances.length == 0)
			return [];
		string[] strings = new string[chain.identifiersOrTemplateInstances.length];
		for (size_t i = 0; i < chain.identifiersOrTemplateInstances.length; ++i)
		{
			auto identOrTemplate = chain.identifiersOrTemplateInstances[i];
			if (identOrTemplate is null)
				continue;
			strings[i] = stringCache.intern(identOrTemplate.templateInstance is null ?
				identOrTemplate.identifier.text
				: identOrTemplate.templateInstance.identifier.text);
		}
		return strings;
	}

	static ACSymbol* processSuffix(ACSymbol* symbol, const TypeSuffix suffix)
	{
		import std.container;
		import formatter;
		if (suffix.star)
			return symbol;
		if (suffix.array || suffix.type)
		{
			ACSymbol* s = new ACSymbol(null);
			s.parts = new RedBlackTree!(ACSymbol*, comparitor, true);
			s.parts.insert(suffix.array ? (cast() arraySymbols)[]
				: (cast() assocArraySymbols)[]);
			s.type = symbol;
			s.qualifier = suffix.array ? SymbolQualifier.array : SymbolQualifier.assocArray;
			return s;
		}
		if (suffix.parameters)
		{
			import conversion.first;
			ACSymbol* s = new ACSymbol(null);
			s.type = symbol;
			s.qualifier = SymbolQualifier.func;
			s.callTip = suffix.delegateOrFunction.text ~ formatNode(suffix.parameters);
			return s;
		}
		return null;
	}

	static ACSymbol* convertBuiltinType(const Type2 type2)
	{
		string stringRepresentation = str(type2.builtinType);
		if (stringRepresentation is null) return null;
		// TODO: Make this use binary search instead
		auto t = cast() builtinSymbols;
		ACSymbol s = ACSymbol(stringRepresentation);
		return t.equalRange(&s).front();
	}

	shared(StringCache)* stringCache;
}
