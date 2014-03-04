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
import stdx.d.ast;
import stdx.d.lexer;
import stupidlog;

/**
 * Intermediate form between ACSymbol and the AST classes. Stores enough
 * information to resolve things like base classes and alias this.
 */
struct SemanticSymbol
{
public:

	@disable this();

	/**
	 * Params:
	 *    name = the name
	 *    kind = the completion kind
	 *    symbolFile = the file name for this symbol
	 *    location = the location of this symbol
	 */
	this(string name, CompletionKind kind, string symbolFile,
		size_t location = size_t.max, const Type type = null)
	{
		acSymbol = new ACSymbol(name, kind);
		acSymbol.location = location;
		acSymbol.symbolFile = symbolFile;
		this.type = type;
	}

	/**
	 * Adds a child to the children field and updates the acSymbol's parts field
	 */
	void addChild(SemanticSymbol* child)
	{
		children ~= child;
		acSymbol.parts.insert(child.acSymbol);
	}

	/// Autocompletion symbol
	ACSymbol* acSymbol;

	/// Base classes
	string[][] baseClasses;

	/// Variable type or function return type
	const Type type;

	/// Alias this symbols
	string[] aliasThis;

	/// MixinTemplates
	string[] mixinTemplates;

	/// Protection level for this symobol
	IdType protection;

	/// Parent symbol
	SemanticSymbol* parent;

	/// Child symbols
	SemanticSymbol*[] children;
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
	// _argptr has type void*
	argptrType = new Type;
	argptrType.type2 = new Type2;
	argptrType.type2.builtinType = tok!"void";
	TypeSuffix argptrTypeSuffix = new TypeSuffix;
	argptrTypeSuffix.star = true;
	argptrType.typeSuffixes ~= argptrTypeSuffix;

	// _arguments has type TypeInfo[]
	argumentsType = new Type;
	argumentsType = new Type;
	argumentsType.type2 = new Type2;
	argumentsType.type2.symbol = new Symbol;
	argumentsType.type2.symbol.identifierOrTemplateChain = new IdentifierOrTemplateChain;
	IdentifierOrTemplateInstance i = new IdentifierOrTemplateInstance;
	i.identifier.text = "TypeInfo";
	i.identifier.type = tok!"identifier";
	argumentsType.type2.symbol.identifierOrTemplateChain.identifiersOrTemplateInstances ~= i;
	TypeSuffix argumentsTypeSuffix = new TypeSuffix;
	argumentsTypeSuffix.array = true;
	argumentsType.typeSuffixes ~= argptrTypeSuffix;
}
