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

import std.d.ast;
import std.d.lexer;
import conversion.second;
import semantic;
import actypes;
import messages;
import std.allocator;
import string_interning;

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
		this.name = name;
		this.symbolAllocator = second.symbolAllocator;
	}

	string name;

	void run()
	{
		thirdPass(rootSymbol);
	}

	SemanticSymbol* rootSymbol;
	Scope* moduleScope;
	CAllocator symbolAllocator;

private:

	void thirdPass(SemanticSymbol* currentSymbol)
	{
//		Log.trace("third pass on ", currentSymbol.acSymbol.name);
		with (CompletionKind) final switch (currentSymbol.acSymbol.kind)
		{
		case className:
		case interfaceName:
			resolveInheritance(currentSymbol);
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
		case structName:
		case unionName:
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

		with (CompletionKind) switch (currentSymbol.acSymbol.kind)
		{
		case className:
		case interfaceName:
		case structName:
		case unionName:
			resolveAliasThis(currentSymbol);
			resolveMixinTemplates(currentSymbol);
			break;
		default:
			break;
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
		foreach (aliasThis; currentSymbol.aliasThis)
		{
			auto parts = currentSymbol.acSymbol.getPartsByName(aliasThis);
			if (parts.length == 0 || parts[0].type is null)
				continue;
			currentSymbol.acSymbol.aliasThisParts.insert(parts[0].type.parts[]);
		}
	}

	void resolveMixinTemplates(SemanticSymbol*)
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
			size_t l = t.type2.symbol.identifierOrTemplateChain.identifiersOrTemplateInstances.length;
			string[] symbolParts = (cast(string*) Mallocator.it.allocate(l * string.sizeof))[0 .. l];
			scope(exit) Mallocator.it.deallocate(symbolParts);
			expandSymbol(symbolParts, t.type2.symbol.identifierOrTemplateChain);
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

	static void expandSymbol(string[] strings, const IdentifierOrTemplateChain chain)
	{
		for (size_t i = 0; i < chain.identifiersOrTemplateInstances.length; ++i)
		{
			auto identOrTemplate = chain.identifiersOrTemplateInstances[i];
			if (identOrTemplate is null)
			{
				strings[i] = null;
				continue;
			}
			strings[i] = internString(identOrTemplate.templateInstance is null ?
				identOrTemplate.identifier.text
				: identOrTemplate.templateInstance.identifier.text);
		}
	}

	ACSymbol* processSuffix(ACSymbol* symbol, const TypeSuffix suffix)
	{
		import std.d.formatter;
		if (suffix.star)
			return symbol;
		if (suffix.array || suffix.type)
		{
			ACSymbol* s = allocate!ACSymbol(symbolAllocator, null);
			s.parts.insert(suffix.array ? arraySymbols[]
				: assocArraySymbols[]);
			s.type = symbol;
			s.qualifier = suffix.array ? SymbolQualifier.array : SymbolQualifier.assocArray;
			return s;
		}
		if (suffix.parameters)
		{
			import conversion.first;
			import memory.allocators;
			import memory.appender;
			ACSymbol* s = allocate!ACSymbol(symbolAllocator, null);
			s.type = symbol;
			s.qualifier = SymbolQualifier.func;
			QuickAllocator!1024 q;
			auto app = Appender!(char, typeof(q), 1024)(q);
			scope(exit) q.deallocate(app.mem);
			app.append(suffix.delegateOrFunction.text);
			app.formatNode(suffix.parameters);
			s.callTip = internString(cast(string) app[]);
			return s;
		}
		return null;
	}

	ACSymbol* convertBuiltinType(const Type2 type2)
	{
		import std.stdio;
		string stringRepresentation = getBuiltinTypeName(type2.builtinType);
//		writefln(">> %s %016X", stringRepresentation, stringRepresentation.ptr);
		ACSymbol s = ACSymbol(stringRepresentation);
		assert(s.name.ptr == stringRepresentation.ptr);
//		writefln(">> %s %016X", s.name, s.name.ptr);
		return builtinSymbols.equalRange(&s).front();
	}
}
