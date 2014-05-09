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

module semantic;

import messages;
import actypes;
import std.d.ast;
import std.d.lexer;
import stupidlog;
import containers.unrolledlist;

/**
 * Intermediate form between ACSymbol and the AST classes. Stores enough
 * information to resolve things like base classes and alias this.
 */
struct SemanticSymbol
{
public:

	@disable this();
	@disable this(this);

	/**
	 * Params:
	 *    name = the name
	 *    kind = the completion kind
	 *    symbolFile = the file name for this symbol
	 *    location = the location of this symbol
	 */
	this(ACSymbol* acSymbol, const Type type = null)
	{
		this.acSymbol = acSymbol;
		this.type = type;
	}

	~this()
	{
		foreach (child; children[])
			typeid(typeof(*child)).destroy(child);
	}

	/**
	 * Adds a child to the children field and updates the acSymbol's parts field
	 */
	void addChild(SemanticSymbol* child)
	{
		children.insert(child);
		acSymbol.parts.insert(child.acSymbol);
	}

	/// Autocompletion symbol
	ACSymbol* acSymbol;

	/// Base classes
	UnrolledList!(string[]) baseClasses;

	/// Variable type or function return type
	const Type type;

	/// Alias this symbols
	UnrolledList!(string) aliasThis;

	/// MixinTemplates
	UnrolledList!(string) mixinTemplates;

	/// Protection level for this symobol
	IdType protection;

	/// Parent symbol
	SemanticSymbol* parent;

	/// Child symbols
	UnrolledList!(SemanticSymbol*) children;
}

/**
 * Type of the _argptr variable
 */
Type argptrType;

/**
 * Type of _arguments
 */
Type argumentsType;

static this()
{
	import std.allocator;
	// _argptr has type void*
	argptrType = allocate!Type(Mallocator.it);
	argptrType.type2 = allocate!Type2(Mallocator.it);
	argptrType.type2.builtinType = tok!"void";
	TypeSuffix argptrTypeSuffix = allocate!TypeSuffix(Mallocator.it);
	argptrTypeSuffix.star = true;
	argptrType.typeSuffixes = cast(TypeSuffix[]) Mallocator.it.allocate(TypeSuffix.sizeof);
	argptrType.typeSuffixes[0] = argptrTypeSuffix;

	// _arguments has type TypeInfo[]
	argumentsType = allocate!Type(Mallocator.it);
	argumentsType.type2 = allocate!Type2(Mallocator.it);
	argumentsType.type2.symbol = allocate!Symbol(Mallocator.it);
	argumentsType.type2.symbol.identifierOrTemplateChain = allocate!IdentifierOrTemplateChain(Mallocator.it);
	IdentifierOrTemplateInstance i = allocate!IdentifierOrTemplateInstance(Mallocator.it);
	i.identifier.text = "TypeInfo";
	i.identifier.type = tok!"identifier";
	argumentsType.type2.symbol.identifierOrTemplateChain.identifiersOrTemplateInstances =
		cast(IdentifierOrTemplateInstance[]) Mallocator.it.allocate(IdentifierOrTemplateInstance.sizeof);
	argumentsType.type2.symbol.identifierOrTemplateChain.identifiersOrTemplateInstances[0] = i;
	TypeSuffix argumentsTypeSuffix = allocate!TypeSuffix(Mallocator.it);
	argumentsTypeSuffix.array = true;
	argumentsType.typeSuffixes = cast(TypeSuffix[]) Mallocator.it.allocate(TypeSuffix.sizeof);
	argumentsType.typeSuffixes[0] = argptrTypeSuffix;
}
