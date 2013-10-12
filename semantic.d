/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2013 Brian Schott
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

/**
 * Intermediate form between ACSymbol and the AST classes. Stores enough
 * information to resolve things like base classes and alias this.
 */
struct SemanticSymbol
{
public:

	void name(string n) @property { acSymbol.name = n; }

	void addChild(SemanticSymbol* child)
	{
		children ~= child;
		acSymbol.parts ~= child.acSymbol;
	}

	/// Autocompletion symbol
	ACSymbol* acSymbol;

	/// Base classes
	string[][] baseClasses;

	/// Variable type or function return type
	Type type;

	/// Alias this symbols
	string[] aliasThis;

	/// MixinTemplates
	string[] mixinTemplates;

	/// Protection level for this symobol
	TokenType protection;

	mixin scopeImplementation!(SemanticSymbol);
}
