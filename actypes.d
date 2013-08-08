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

module actypes;

import stdx.d.lexer;
import stdx.d.ast;
import std.algorithm;
import std.stdio;
import messages;

/**
 * Autocompletion symbol
 */
class ACSymbol
{
public:

	this()
	{
	}

	this(string name)
	{
		this.name = name;
	}

	this(string name, CompletionKind kind)
	{
		this.name = name;
		this.kind = kind;
	}

	this(string name, CompletionKind kind, ACSymbol resolvedType)
	{
		this.name = name;
		this.kind = kind;
		this.resolvedType = resolvedType;
	}

	/**
	 * Symbols that compose this symbol, such as enum members, class variables,
	 * methods, etc.
	 */
    ACSymbol[] parts;

	/**
	 * Symbol's name
	 */
    string name;

	size_t location;

	/**
	 * The kind of symbol
	 */
    CompletionKind kind;

	/**
	 * The return type if this is a function, or the element type if this is an
	 * array or associative array, or the variable type if this is a variable.
	 * This field is null if this symbol is a class
	 */
	Type type;

	ACSymbol resolvedType;

	/**
	 * Finds symbol parts by name
	 */
	ACSymbol getPartByName(string name)
	{
		foreach (part; parts)
		{
			if (part.name == name)
				return part;
		}
		return null;
	}
}

/**
 * Scope such as a block statement, struct body, etc.
 */
class Scope
{
public:

	/**
	 * Params:
	 *     start = the index of the opening brace
	 *     end = the index of the closing brace
	 */
	this(size_t start, size_t end)
	{
		this.start = start;
		this.end = end;
	}

	/**
	 * Finds the scope containing the cursor position, then searches for a
	 * symbol with the given name.
	 */
	ACSymbol findSymbolInCurrentScope(size_t cursorPosition, string name)
	{
		auto s = findCurrentScope(cursorPosition);
		if (s is null)
		{
			writeln("Could not find scope");
			return null;
		}
		else
			return s.findSymbolInScope(name);
	}

    /**
     * Returns: the innermost Scope that contains the given cursor position.
     */
    Scope findCurrentScope(size_t cursorPosition)
    {
        if (start != size_t.max && (cursorPosition < start || cursorPosition > end))
            return null;
        foreach (sc; children)
        {
            auto s = sc.findCurrentScope(cursorPosition);
            if (s is null)
                continue;
            else
                return s;
        }
        return this;
    }

	/**
	 * Finds a symbol with the given name in this scope or one of its parent
	 * scopes.
	 */
    ACSymbol findSymbolInScope(string name)
    {
		foreach (symbol; symbols)
		{
			if (symbol.name == name)
				return symbol;
		}
		if (parent !is null)
			return parent.findSymbolInScope(name);
        return null;
    }

	void resolveSymbolTypes()
	{
		foreach (s; symbols.filter!(a => a.kind == CompletionKind.variableName)())
		{
			Type type = s.type;
			if (type.typeSuffixes.length == 0)
			{
				if (type.type2.builtinType != TokenType.invalid)
				{
					s.resolvedType = findSymbolInCurrentScope(s.location,
						getTokenValue(type.type2.builtinType));
				}
				else if (type.type2.symbol !is null)
				{
					Symbol sym = type.type2.symbol;
					if (sym.identifierOrTemplateChain.identifiersOrTemplateInstances.length != 1)
						return;
					s.resolvedType = findSymbolInCurrentScope(s.location,
						sym.identifierOrTemplateChain.identifiersOrTemplateInstances[0].identifier.value);
				}
			}
		}
		foreach (c; children)
		{
			c.resolveSymbolTypes();
		}
	}

	/**
	 * Index of the opening brace
	 */
    size_t start = size_t.max;

	/**
	 * Index of the closing brace
	 */
    size_t end = size_t.max;

	/**
	 * Symbols contained in this scope
	 */
    ACSymbol[] symbols;

	/**
	 * The parent scope
	 */
    Scope parent;

	/**
	 * Child scopes
	 */
    Scope[] children;
}
