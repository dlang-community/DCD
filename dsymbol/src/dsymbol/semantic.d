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

module dsymbol.semantic;

import dsymbol.symbol;
import dparse.ast;
import dparse.lexer;
import containers.unrolledlist;
import dsymbol.type_lookup;
import std.experimental.allocator.mallocator : Mallocator;
import std.experimental.allocator.gc_allocator : GCAllocator;

enum ResolutionFlags : ubyte
{
	inheritance = 0b0000_0001,
	type = 0b0000_0010,
	mixinTemplates = 0b0000_0100,
}

alias TypeLookupsAllocator = GCAllocator; // NOTE using `Mallocator` here fails when analysing Phobos as: `munmap_chunk(): invalid pointer`
alias TypeLookups = UnrolledList!(TypeLookup*, TypeLookupsAllocator);

/**
 * Intermediate form between DSymbol and the AST classes. Stores enough
 * information to resolve things like base classes and alias this.
 */
struct SemanticSymbol
{
public:

	/// Disable default construction.
	@disable this();
	/// Disable copy construction
	@disable this(this);

	/**
	 * Params:
	 *    name = the name
	 */
	this(DSymbol* acSymbol)
	{
		this.acSymbol = acSymbol;
	}

	~this()
	{
		import std.experimental.allocator : dispose;

		foreach (child; children[])
			typeid(SemanticSymbol).destroy(child);
		foreach (lookup; typeLookups[])
			TypeLookupsAllocator.instance.dispose(lookup);
	}

	/**
	 * Adds a child to the children field and updates the acSymbol's parts field
	 */
	void addChild(SemanticSymbol* child, bool owns)
	{
		children.insert(child);
		acSymbol.addChild(child.acSymbol, owns);
	}

	/// Information used to do type resolution, inheritance, mixins, and alias this
	TypeLookups typeLookups;

	/// Child symbols
	UnrolledList!(SemanticSymbol*, GCAllocator) children; // NOTE using `Mallocator` here fails when analysing Phobos

	/// Autocompletion symbol
	DSymbol* acSymbol;

	/// Parent symbol
	SemanticSymbol* parent;

	/// Protection level for this symobol
	deprecated("Use acSymbol.protection instead") ref inout(IdType) protection() @property inout
	{
		return acSymbol.protection;
	}
}

/**
 * Type of the _argptr variable
 */
Type argptrType;

/**
 * Type of _arguments
 */
Type argumentsType;

alias GlobalsAllocator = Mallocator;

static this()
{
	import dsymbol.string_interning : internString;
	import std.experimental.allocator : make;

	// TODO: Replace these with DSymbols

	// _argptr has type void*
	argptrType = GlobalsAllocator.instance.make!Type();
	argptrType.type2 = GlobalsAllocator.instance.make!Type2();
	argptrType.type2.builtinType = tok!"void";
	TypeSuffix argptrTypeSuffix = GlobalsAllocator.instance.make!TypeSuffix();
	argptrTypeSuffix.star = Token(tok!"*");
	argptrType.typeSuffixes = cast(TypeSuffix[]) GlobalsAllocator.instance.allocate(TypeSuffix.sizeof);
	argptrType.typeSuffixes[0] = argptrTypeSuffix;

	// _arguments has type TypeInfo[]
	argumentsType = GlobalsAllocator.instance.make!Type();
	argumentsType.type2 = GlobalsAllocator.instance.make!Type2();
	argumentsType.type2.typeIdentifierPart = GlobalsAllocator.instance.make!TypeIdentifierPart();
	IdentifierOrTemplateInstance i = GlobalsAllocator.instance.make!IdentifierOrTemplateInstance();
	i.identifier.text = internString("TypeInfo");
	i.identifier.type = tok!"identifier";
	argumentsType.type2.typeIdentifierPart.identifierOrTemplateInstance = i;
	TypeSuffix argumentsTypeSuffix = GlobalsAllocator.instance.make!TypeSuffix();
	argumentsTypeSuffix.array = true;
	argumentsType.typeSuffixes = cast(TypeSuffix[]) GlobalsAllocator.instance.allocate(TypeSuffix.sizeof);
	argumentsType.typeSuffixes[0] = argumentsTypeSuffix;
}

static ~this()
{
	import std.experimental.allocator : dispose;
	GlobalsAllocator.instance.dispose(argumentsType.typeSuffixes[0]);
	GlobalsAllocator.instance.dispose(argumentsType.type2.typeIdentifierPart.identifierOrTemplateInstance);
	GlobalsAllocator.instance.dispose(argumentsType.type2.typeIdentifierPart);
	GlobalsAllocator.instance.dispose(argumentsType.type2);
	GlobalsAllocator.instance.dispose(argptrType.typeSuffixes[0]);
	GlobalsAllocator.instance.dispose(argptrType.type2);

	GlobalsAllocator.instance.deallocate(argumentsType.typeSuffixes);
	GlobalsAllocator.instance.deallocate(argptrType.typeSuffixes);

	GlobalsAllocator.instance.dispose(argumentsType);
	GlobalsAllocator.instance.dispose(argptrType);
}
