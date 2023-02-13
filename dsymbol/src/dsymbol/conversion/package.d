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

module dsymbol.conversion;

import dparse.ast;
import dparse.lexer;
import dparse.parser;
import dparse.rollback_allocator;
import dsymbol.cache_entry;
import dsymbol.conversion.first;
import dsymbol.conversion.second;
import dsymbol.conversion.third;
import dsymbol.modulecache;
import dsymbol.scope_;
import dsymbol.semantic;
import dsymbol.string_interning;
import dsymbol.symbol;
import std.algorithm;
import std.experimental.allocator;
import containers.hashset;

/**
 * Used by autocompletion.
 */
ScopeSymbolPair generateAutocompleteTrees(const(Token)[] tokens,
	RollbackAllocator* parseAllocator,
	size_t cursorPosition, ref ModuleCache cache)
{
	Module m = parseModuleForAutocomplete(tokens, internString("stdin"),
		parseAllocator, cursorPosition);

	scope first = new FirstPass(m, internString("stdin"), &cache);
	first.run();

	secondPass(first.rootSymbol, first.moduleScope, cache);

	thirdPass(first.rootSymbol, first.moduleScope, cache, cursorPosition);

	auto r = move(first.rootSymbol.acSymbol);
	typeid(SemanticSymbol).destroy(first.rootSymbol);
	return ScopeSymbolPair(r, move(first.moduleScope));
}

struct ScopeSymbolPair
{
	void destroy()
	{
		typeid(DSymbol).destroy(symbol);
		typeid(Scope).destroy(scope_);
	}

	DSymbol* symbol;
	Scope* scope_;
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
Module parseModuleSimple(const(Token)[] tokens, string fileName, RollbackAllocator* parseAllocator)
{
	assert (parseAllocator !is null);
	scope parser = new SimpleParser();
	parser.fileName = fileName;
	parser.tokens = tokens;
	parser.messageFunction = &doesNothing;
	parser.allocator = parseAllocator;
	return parser.parseModule();
}

private:

Module parseModuleForAutocomplete(const(Token)[] tokens, string fileName,
	RollbackAllocator* parseAllocator, size_t cursorPosition)
{
	scope parser = new AutocompleteParser();
	parser.fileName = fileName;
	parser.tokens = tokens;
	parser.messageFunction = &doesNothing;
	parser.allocator = parseAllocator;
	parser.cursorPosition = cursorPosition;
	return parser.parseModule();
}

class AutocompleteParser : Parser
{
	override BlockStatement parseBlockStatement()
	{
		if (!currentIs(tok!"{"))
			return null;
		if (current.index > cursorPosition)
		{
			BlockStatement bs = allocator.make!(BlockStatement);
			bs.startLocation = current.index;
			skipBraces();
			bs.endLocation = tokens[index - 1].index;
			return bs;
		}
		immutable start = current.index;
		auto b = setBookmark();
		skipBraces();
		if (tokens[index - 1].index < cursorPosition)
		{
			abandonBookmark(b);
			BlockStatement bs = allocator.make!BlockStatement();
			bs.startLocation = start;
			bs.endLocation = tokens[index - 1].index;
			return bs;
		}
		else
		{
			goToBookmark(b);
			return super.parseBlockStatement();
		}
	}

private:
	size_t cursorPosition;
}

class SimpleParser : Parser
{
	override Unittest parseUnittest()
	{
		expect(tok!"unittest");
		if (currentIs(tok!"{"))
			skipBraces();
		return allocator.make!Unittest;
	}

	override MissingFunctionBody parseMissingFunctionBody()
	{
		// Unlike many of the other parsing functions, it is valid and expected
		// for this one to return `null` on valid code. Returning `null` in
		// this function means that we are looking at a SpecifiedFunctionBody
		// or ShortenedFunctionBody.
		//
		// The super-class will handle re-trying with the correct parsing
		// function.

		const bool needDo = skipContracts();
		if (needDo && moreTokens && (currentIs(tok!"do") || current.text == "body"))
			return null;
		if (currentIs(tok!";"))
			advance();
		else
			return null;
		return allocator.make!MissingFunctionBody;
	}

	override SpecifiedFunctionBody parseSpecifiedFunctionBody()
	{
		if (currentIs(tok!"{"))
			skipBraces();
		else
		{
			skipContracts();
			if (currentIs(tok!"do") || (currentIs(tok!"identifier") && current.text == "body"))
				advance();
			if (currentIs(tok!"{"))
				skipBraces();
		}
		return allocator.make!SpecifiedFunctionBody;
	}

	override ShortenedFunctionBody parseShortenedFunctionBody()
	{
		skipContracts();
		if (currentIs(tok!"=>"))
		{
			while (!currentIs(tok!";") && moreTokens)
			{
				if (currentIs(tok!"{")) // potential function literal
					skipBraces();
				else
					advance();
			}
			if (moreTokens)
				advance();
			return allocator.make!ShortenedFunctionBody;
		}
		else
		{
			return null;
		}
	}

	/**
	 * Skip contracts, and return `true` if the type of contract used requires
	 * that the next token is `do`.
	 */
	private bool skipContracts()
	{
		bool needDo;

		while (true)
		{
			if (currentIs(tok!"in"))
			{
				advance();
				if (currentIs(tok!"{"))
				{
					skipBraces();
					needDo = true;
				}
				if (currentIs(tok!"("))
					skipParens();
			}
			else if (currentIs(tok!"out"))
			{
				advance();
				if (currentIs(tok!"("))
				{
					immutable bool asExpr = peekIs(tok!";")
						|| (peekIs(tok!"identifier")
							&& index + 2 < tokens.length && tokens[index + 2].type == tok!";");
					skipParens();
					if (asExpr)
					{
						needDo = false;
						continue;
					}
				}
				if (currentIs(tok!"{"))
				{
					skipBraces();
					needDo = true;
				}
			}
			else
				break;
		}
		return needDo;
	}
}

void doesNothing(string, size_t, size_t, string, bool) {}
