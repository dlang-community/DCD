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
import std.array;
import messages;
import autocomplete;
import std.array;

/**
 * Any special information about a variable declaration symbol.
 */
enum SymbolQualifier
{
	/// _none
	none,
	/// the symbol is an _array
	array,
	/// the symbol is a associative array
	assocArray,
	/// the symbol is a function or delegate pointer
	func
}

/**
 * Autocompletion symbol
 */
class ACSymbol
{
public:

	this() {}

	/**
	 * Params:
	 *     name = the symbol's name
	 */
	this(string name)
	{
		this.name = name;
	}

	/**
	 * Params:
	 *     name = the symbol's name
	 *     kind = the symbol's completion kind
	 */
	this(string name, CompletionKind kind)
	{
		this.name = name;
		this.kind = kind;
	}

	/**
	 * Params:
	 *     name = the symbol's name
	 *     kind = the symbol's completion kind
	 *     resolvedType = the resolved type of the symbol
	 */
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
	 * Listing of superclasses
	 */
	string[] superClasses;

	/**
	 * Symbol's name
	 */
	string name;

	/**
	 * Symbol's location in bytes
	 */
	size_t location;

	/**
	 * Any special information about this symbol
	 */
	SymbolQualifier qualifier;

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

	/**
	 * The symbol that represents the type. _resolvedType is an autocomplete
	 * class, type is an AST class, so after a module is parsed the symbols
	 * need to be post-processed to tie variable declarations to the symbols
	 * that actually contain the correct autocomplete information.
	 */
	ACSymbol resolvedType;

	/**
	 * Calltip to display if this is a function
	 */
	string calltip;

	/**
	 * Finds symbol parts by name
	 */
	ACSymbol[] getPartsByName(string name)
	{
		return parts.filter!(a => a.name == name).array;
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
	 * Gets all symbols in the scope that contains the cursor as well as its
	 * parent scopes.
	 */
	ACSymbol[] getSymbolsInCurrentScope(size_t cursorPosition)
	{
		Scope s = findCurrentScope(cursorPosition);
		if (s is null)
			return [];
		else
			return s.getSymbols();
	}

	/**
	 * Gets all symbols in this scope and its parent scopes.
	 */
	ACSymbol[] getSymbols()
	{
		ACSymbol[] rVal;
		rVal ~= symbols;
		if (parent !is null)
			rVal ~= parent.getSymbols();
		return rVal;
	}

	/**
	 * Finds the scope containing the cursor position, then searches for a
	 * symbol with the given name.
	 */
	ACSymbol[] findSymbolsInCurrentScope(size_t cursorPosition, string name)
	{
		auto s = findCurrentScope(cursorPosition);
		if (s is null)
		{
			writeln("Could not find scope");
			return [];
		}
		else
			return s.findSymbolsInScope(name);
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
	ACSymbol[] findSymbolsInScope(string name)
	{
		ACSymbol[] currentMatches = symbols.filter!(a => a.name == name)().array();
		if (currentMatches.length == 0 && parent !is null)
			return parent.findSymbolsInScope(name);
	    return currentMatches;
	}

	/**
	 * Fills in the $(D resolvedType) fields of the symbols in this scope and
	 * all child scopes.
	 */
	void resolveSymbolTypes()
	{
		// We only care about resolving types of variables, all other symbols
		// don't have any indirection
		foreach (ref s; symbols.filter!(a => (a.kind == CompletionKind.variableName
			|| a.kind == CompletionKind.functionName || a.kind == CompletionKind.memberVariableName
			|| a.kind == CompletionKind.enumMember || a.kind == CompletionKind.aliasName)
			&& a.resolvedType is null)())
		{
			//writeln("Resolving type of symbol ", s.name);
			Type type = s.type;
			if (type is null)
			{
				//writeln("Could not find it due to null type");
				continue;
			}
			if (type.type2.builtinType != TokenType.invalid)
			{
				// This part is easy. Autocomplete properties of built-in types
				auto foundSymbols = findSymbolsInScope(getTokenValue(type.type2.builtinType));
				s.resolvedType = foundSymbols[0];
			}
			else if (type.type2.symbol !is null)
			{
				// Look up a type by its name for cases like class, enum,
				// interface, struct, or union members.

				// TODO: Does not work with qualified names or template instances
				Symbol sym = type.type2.symbol;
				if (sym.identifierOrTemplateChain.identifiersOrTemplateInstances.length != 1)
				{
					writeln("Could not resolve type");
					continue;
				}
				ACSymbol[] resolvedType = findSymbolsInCurrentScope(s.location,
					sym.identifierOrTemplateChain.identifiersOrTemplateInstances[0].identifier.value);
				if (resolvedType.length > 0 && (resolvedType[0].kind == CompletionKind.interfaceName
					|| resolvedType[0].kind == CompletionKind.className
					|| resolvedType[0].kind == CompletionKind.aliasName
					|| resolvedType[0].kind == CompletionKind.unionName
					|| resolvedType[0].kind == CompletionKind.structName))
				{
//					writeln("Type resolved to ", resolvedType[0].name, " which has kind ",
//						resolvedType[0].kind, " and call tip ", resolvedType[0].calltip);
					s.resolvedType = resolvedType[0];
				}
			}

			foreach (suffix; type.typeSuffixes)
			{
				//writeln("Handling type suffix");
				// Handle type suffixes for declarations, e.g.:
				// int[] a;
				// SomeClass[string] b;
				// double function(double, double) c;
				auto sym = s.resolvedType;
				s.resolvedType = new ACSymbol;
				s.resolvedType.resolvedType = sym;
				if (suffix.array)
				{
					if (suffix.type !is null)
					{
						// assocative array
						s.resolvedType.qualifier = SymbolQualifier.assocArray;
						s.resolvedType.parts ~= assocArraySymbols;
					}
					else
					{
						// normal array
						s.resolvedType.qualifier = SymbolQualifier.array;
						s.resolvedType.parts ~= arraySymbols;
					}
				}
				else if (suffix.delegateOrFunction.type != TokenType.invalid)
				{
					s.resolvedType.qualifier = SymbolQualifier.func;
				}
			}
		}

		foreach (c; children)
		{
			c.resolveSymbolTypes();
		}

		foreach (ref ACSymbol c; symbols.filter!(a => a.kind == CompletionKind.className
			|| a.kind == CompletionKind.interfaceName))
		{
			foreach (string sc; c.superClasses)
			{
				//writeln("Adding inherited fields from ", sc);
				ACSymbol[] s = findSymbolsInScope(sc);
				if (s.length > 0)
				{
					foreach (part; s[0].parts)
						c.parts ~= part;
				}
			}
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
