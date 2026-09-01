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

module dcd.server.autocomplete.inlayhints;

import std.stdio;
import std.algorithm;
import std.array;
import std.experimental.allocator;
import std.experimental.logger;
import std.typecons;

import dcd.server.autocomplete.util;

import dparse.lexer;
import dparse.rollback_allocator;

import dsymbol.modulecache;
import dsymbol.symbol;
import dsymbol.scope_;
import dsymbol.conversion;
import dsymbol.string_interning;

import dcd.common.messages;

import containers.hashset;

/**
 * Renders a type chain into `c.identifier` as a readable D type name.
 * dsymbol models arrays/pointers/AAs as dummy placeholder symbols named
 * "*arr*" etc.; this turns those into D syntax ("[]", "[..]", "*")
 * instead of leaking the placeholders into the hint label.
 */
private void appendType(ref AutocompleteResponse.Completion c, const(DSymbol)* t)
{
	if (t is null)
		return;
	if (t.qualifier == SymbolQualifier.array)
	{
		appendType(c, t.type);
		c.identifier ~= "[]";
	}
	else if (t.qualifier == SymbolQualifier.assocArray)
	{
		// value type is the child; key is not exposed
		appendType(c, t.type);
		c.identifier ~= "[..]";
	}
	else if (t.qualifier == SymbolQualifier.pointer)
	{
		appendType(c, t.type);
		c.identifier ~= "*";
	}
	else if (t.name !is null && t.name.length
		&& !canFind(t.name[], '*'))
	{
		c.identifier ~= t.name;
	}
}

public AutocompleteResponse getInlayHints(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
//	trace("Getting inlay hints comments");
	AutocompleteResponse response;

	LexerConfig config;
	config.fileName = "";
	// clampedBucketCount guards against the empty-document crash
	auto cache = StringCache(clampedBucketCount(request.sourceCode.length));
	auto tokenArray = getTokensForParser(cast(ubyte[]) request.sourceCode, config, &cache);
	RollbackAllocator rba;
	auto pair = generateAutocompleteTrees(tokenArray, &rba, -1, moduleCache);
	scope(exit) pair.destroy();

	void check(DSymbol* it, ref HashSet!size_t visited, bool inFunctionParams = false)
	{
		if (visited.contains(cast(size_t) it))
			return;
		if (it.symbolFile != "stdin") return;
		visited.insert(cast(size_t) it);

		//writeln("sym: ", it.name," ", it.location, " kind: ", it.kind," qualifier: ", it.qualifier);
		//if (auto type = it.type)
		//{
		//	writeln("   ", type.name, " kind: ", type.kind, " qualifier", type.qualifier);
		//	if (auto ttype = type.type)
		//		writeln("      ", ttype.name, " kind: ", ttype.kind, " qualifier", ttype.qualifier);
		//}

		// Function parameters always have their type spelled out in the
		// source — a hint there is pure noise.
		const isParam = inFunctionParams
			&& it.kind == CompletionKind.variableName;

		// aliases
		// 		struct Data {}
		// 		alias Alias1 = Data;
		// 		Alias1 var;				renders:  var: Data
		// Builtin aliases (string/wstring/dstring) are skipped: they are
		// idiomatic D, so resolving them is noise — and the resolved label
		// would be wrong anyway (string is immutable(char)[], but the
		// placeholder-symbol type chain cannot express the immutable).
		if (!isParam && it.kind == CompletionKind.variableName && it.type
			&& it.type.kind == CompletionKind.aliasName
			&& !isBuiltinAlias(it.type.name))
		{
			AutocompleteResponse.Completion c;
			// Position the hint right after the variable name so editors
		// render it in the conventional "name: type" form (like clangd
		// and rust-analyzer do for deduced types).
			c.symbolLocation = it.location + (it.name is null ? 0 : it.name.length);
			c.symbolFilePath = "stdin";
			c.kind = CompletionKind.aliasName;

			// Resolve the alias chain to the underlying type and show that;
			// e.g. for "alias P = Point; P p;" the hint is "p:Point".
			c.identifier = ":";
			DSymbol* type = it.type;
			while (type.type && type.type.kind == CompletionKind.aliasName)
				type = type.type;
			appendType(c, type.type !is null ? type.type : type);

			// nothing renderable behind the alias — skip instead of
			// emitting a bare ": " label
			if (c.identifier.length > 2)
				response.completions ~= c;
		}

		// variable types: show the resolved type only for variables whose
		// type is NOT spelled out in the declaration, i.e. inferred via
		// `auto`/`const`/`immutable`/`enum`. Explicitly typed declarations
		// (`Mama mama`, function parameters) already show the type next to
		// the name — a hint there would be redundant. String literals are
		// also skipped: their type is self-evident.
		else if (!isParam && it.kind == CompletionKind.variableName && it.type
			&& it.type.name !is null && it.type.name.length
			&& it.type.name != it.name
			&& typeIsInferred(request.sourceCode, it.location)
			&& !initializerIsStringLiteral(request.sourceCode, it.location,
				it.name is null ? 0 : it.name.length))
		{
			AutocompleteResponse.Completion c;
			// hint goes right after the name: "auto a: Mama = ..."
			c.symbolLocation = it.location + (it.name is null ? 0 : it.name.length);
			c.symbolFilePath = "stdin";
			c.kind = CompletionKind.className;

			appendType(c, it.type);

			if (c.identifier.length)
			{
				c.identifier = ":" ~ c.identifier;
				response.completions ~= c;
			}
		}

		foreach(part; it.opSlice())
			check(part, visited, inFunctionParams || it.functionParameters.length > 0);
	}

	HashSet!size_t visited;
	foreach (symbol; pair.scope_.symbols)
	{
		check(symbol, visited);
		foreach(part; symbol.opSlice())
			check(part, visited);
	}

	response.completions.sort!"a.symbolLocation < b.symbolLocation";

	return response;
}

/**
 * Returns: true if the variable whose name starts at `nameStart` has its
 * type inferred rather than spelled out in the source, i.e. the name is
 * directly preceded by a type-inferring storage class (`auto`, `const`,
 * `immutable`, `enum`). Explicitly typed declarations (`Mama mama`,
 * function parameters — which in D always carry a type) and continued
 * declarators (`int a = 1, b = 2`) already show the type in the source, so
 * a hint there would be redundant.
 */
private bool typeIsInferred(const(ubyte)[] source, size_t nameStart)
{
	if (nameStart == 0 || nameStart > source.length)
		return false;

	// find the last non-whitespace byte before the name
	size_t i = nameStart;
	while (i > 0 && isWhitespace(source[i - 1]))
		i--;
	if (i == 0)
		return false;

	// punctuation directly before the name means an explicit (possibly
	// complex) type (`const(char)[] x`, `int* p`) or a continued declarator
	// (`int a = 1, b = 2`) — no hint needed either way
	if (!isIdentChar(source[i - 1]))
		return false;

	// extract the word ending right before the name
	size_t end = i;
	size_t begin = end;
	while (begin > 0 && isIdentChar(source[begin - 1]))
		begin--;
	const word = cast(string) source[begin .. end];

	// storage classes that infer the type when adjacent to the name
	return word == "auto" || word == "const" || word == "immutable"
		|| word == "enum";
}

private bool isIdentChar(ubyte c) pure nothrow @safe @nogc
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
		|| (c >= '0' && c <= '9') || c == '_';
}

private bool isWhitespace(ubyte c) pure nothrow @safe @nogc
{
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
		|| c == '\v' || c == '\f';
}

/**
 * Returns: true if `name` is one of the builtin alias types (string,
 * wstring, dstring) that D programmers read as-is. Resolving these in a
 * hint is noise, and the placeholder-symbol type chain cannot express the
 * immutable element type anyway (string is immutable(char)[]).
 */
private bool isBuiltinAlias(istring name)
{
	if (name is null)
		return false;
	return name == "string" || name == "wstring" || name == "dstring";
}

/**
 * Returns: true if the variable starting at `nameStart` (name length
 * `nameLength`) is initialized with a string literal. The type of a
 * string literal is self-evident, so a type hint would be noise.
 */
private bool initializerIsStringLiteral(const(ubyte)[] source,
	size_t nameStart, size_t nameLength)
{
	size_t i = nameStart + nameLength;
	// skip whitespace up to the '=' of the initializer
	while (i < source.length && isWhitespace(source[i]))
		i++;
	if (i >= source.length || source[i] != '=')
		return false;
	i++;
	while (i < source.length && isWhitespace(source[i]))
		i++;
	if (i >= source.length)
		return false;
	// double-quoted and wysiwyg (backtick) strings
	if (source[i] == '"' || source[i] == '`')
		return true;
	// r"..." raw, x"..." hex, q"..." delimited strings
	if ((source[i] == 'r' || source[i] == 'x' || source[i] == 'q')
		&& i + 1 < source.length && source[i + 1] == '"')
		return true;
	// q{...} token strings
	if (source[i] == 'q' && i + 1 < source.length
		&& (source[i + 1] == '{' || source[i + 1] == '['
			|| source[i + 1] == '(' || source[i + 1] == '<'))
		return true;
	return false;
}
