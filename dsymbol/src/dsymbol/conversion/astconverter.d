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

module dsymbol.conversion.astconverter;

import dsymbol.conversion.first;
import dsymbol.conversion.second;
import dsymbol.conversion.third;
import dsymbol.scope_;
import dsymbol.string_interning;
import dsymbol.symbol;
import memory.allocators;
import std.allocator;
import std.d.ast;
import std.d.lexer;
import std.d.parser;
import std.typecons;

/**
 * Used by autocompletion.
 */
Scope* generateAutocompleteTrees(const(Token)[] tokens, CAllocator symbolAllocator)
{
	Module m = parseModule(tokens, internString("stdin"), symbolAllocator, &doesNothing);
	auto first = scoped!FirstPass(m, internString("stdin"), symbolAllocator, symbolAllocator);
	first.run();

	SecondPass second = SecondPass(first);
	second.run();

	ThirdPass third = ThirdPass(second);
	third.run();
	typeid(typeof(third.rootSymbol)).destroy(third.rootSymbol);
	return third.moduleScope;
}

/**
 * Used by import symbol caching.
 *
 * Params:
 *     tokens = the tokens that compose the file
 *     fileName = the name of the file being parsed
 *     parseAllocator = the allocator to use for the AST
 * Returns: the parsed module
 */
Module parseModuleSimple(const(Token)[] tokens, string fileName, CAllocator parseAllocator)
{
	auto parser = scoped!SimpleParser();
	parser.fileName = fileName;
	parser.tokens = tokens;
	parser.messageFunction = &doesNothing;
	parser.allocator = parseAllocator;
	return parser.parseModule();
}

private:

class SimpleParser : Parser
{
	override Unittest parseUnittest()
	{
		expect(tok!"unittest");
		if (currentIs(tok!"{"))
			skipBraces();
		return null;
	}

	override FunctionBody parseFunctionBody()
	{
		if (currentIs(tok!";"))
			advance();
		else if (currentIs(tok!"{"))
			skipBraces();
		else
		{
			if (currentIs(tok!"in"))
			{
				advance();
				if (currentIs(tok!"{"))
					skipBraces();
				if (currentIs(tok!"out"))
				{
					advance();
					if (currentIs(tok!"("))
						skipParens();
					if (currentIs(tok!"{"))
						skipBraces();
				}
			}
			else if (currentIs(tok!"out"))
			{
				advance();
				if (currentIs(tok!"("))
					skipParens();
				if (currentIs(tok!"{"))
					skipBraces();
				if (currentIs(tok!"in"))
				{
					advance();
					if (currentIs(tok!"{"))
						skipBraces();
				}
			}
			expect(tok!"body");
			if (currentIs(tok!"{"))
				skipBraces();
		}
		return allocate!FunctionBody();
	}
}

void doesNothing(string, size_t, size_t, string, bool) {}
