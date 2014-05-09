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

module conversion.astconverter;

import actypes;
import conversion.first;
import conversion.second;
import conversion.third;
import memory.allocators;
import std.allocator;
import std.d.ast;
import std.d.lexer;
import std.d.parser;
import std.typecons;

Scope* generateAutocompleteTrees(const(Token)[] tokens, string symbolFile,
	CAllocator symbolAllocator, CAllocator semanticAllocator,
	shared(StringCache)* cache)
{
	Module m = parseModule(tokens, "editor buffer", semanticAllocator, &doesNothing);
	auto first = scoped!FirstPass(m, symbolFile, cache, symbolAllocator,
		semanticAllocator);
	first.run();

	SecondPass second = SecondPass(first);
	second.run();

	ThirdPass third = ThirdPass(second);
	third.run();
	typeid(typeof(third.rootSymbol)).destroy(third.rootSymbol);
	return third.moduleScope;
}

Module parseModuleSimple(const(Token)[] tokens, string fileName, CAllocator p)
{
	auto parser = scoped!SimpleParser();
	parser.fileName = fileName;
	parser.tokens = tokens;
	parser.messageFunction = &doesNothing;
	parser.allocator = p;
	return parser.parseModule();
}

private:

class SimpleParser : Parser
{
	override Unittest parseUnittest()
	{
		expect(tok!"unittest");
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
		return null;
	}
}

void doesNothing(string a, size_t b, size_t c, string d, bool e) {}
