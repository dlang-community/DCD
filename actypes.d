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

import stdx.d.ast;
import std.algorithm;
import std.stdio;
import messages;

class ACSymbol
{
public:
    ACSymbol[] parts;
    string name;
    CompletionKind kind;
    Type[string] templateParameters;
}

class Scope
{
public:

	this(size_t start, size_t end)
	{
		this.start = start;
		this.end = end;
	}

	const(ACSymbol) findSymbolInCurrentScope(size_t cursorPosition, string name) const
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
     * @return the innermost Scope that contains the given cursor position.
     */
    const(Scope) findCurrentScope(size_t cursorPosition) const
    {
        if (cursorPosition < start || cursorPosition > end)
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

    const(ACSymbol) findSymbolInScope(string name) const
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

    size_t start;
    size_t end;
    ACSymbol[] symbols;
    Scope parent;
    Scope[] children;
}
