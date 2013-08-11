/*******************************************************************************
 * Authors: Brian Schott
 * Copyright: Brian Schott
 * Date: Jul 19 2013
 *
 * License:
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
 ******************************************************************************/

module autocomplete;

import std.algorithm;
import std.array;
import std.conv;
import stdx.d.ast;
import stdx.d.lexer;
import stdx.d.parser;
import std.range;
import std.stdio;
import std.uni;

import messages;
import acvisitor;
import actypes;
import constants;


AutocompleteResponse complete(AutocompleteRequest request, string[] importPaths)
{
	writeln("Got a completion request");
	AutocompleteResponse response;

	LexerConfig config;
	auto tokens = request.sourceCode.byToken(config);
	auto tokenArray = tokens.array();
	auto sortedTokens = assumeSorted(tokenArray);

	auto beforeTokens = sortedTokens.lowerBound(cast(size_t) request.cursorPosition);

	if (beforeTokens.length >= 2 && beforeTokens[$ - 1] == TokenType.lParen)
	{
		immutable(string)[] completions;
		switch (beforeTokens[$ - 2].type)
		{
		case TokenType.traits:
			completions = traits;
			goto fillResponse;
		case TokenType.scope_:
			completions = scopes;
			goto fillResponse;
		case TokenType.version_:
			completions = versions;
			goto fillResponse;
		case TokenType.extern_:
			completions = linkages;
			goto fillResponse;
		case TokenType.pragma_:
			completions = pragmas;
		fillResponse:
			response.completionType = CompletionType.identifiers;
			for (size_t i = 0; i < completions.length; i++)
			{
				response.completions ~= completions[i];
				response.completionKinds ~= CompletionKind.keyword;
			}
			break;
		case TokenType.identifier:
		case TokenType.rParen:
		case TokenType.rBracket:
			auto visitor = processModule(tokenArray);
			auto expression = getExpression(beforeTokens[0 .. $ - 1]);
			response.setCompletions(visitor, expression, request.cursorPosition,
				CompletionType.calltips);
			break;
		default:
			break;
		}
	}
	else if (beforeTokens.length >= 2 && beforeTokens[$ - 1] ==  TokenType.dot)
	{
		switch (beforeTokens[$ - 2].type)
		{
		case TokenType.stringLiteral:
		case TokenType.wstringLiteral:
		case TokenType.dstringLiteral:
			foreach (symbol; arraySymbols)
			{
				response.completionKinds ~= symbol.kind;
				response.completions ~= symbol.name;
			}
			response.completionType = CompletionType.identifiers;
			break;
		case TokenType.int_:
		case TokenType.uint_:
		case TokenType.long_:
		case TokenType.ulong_:
		case TokenType.char_:
		case TokenType.wchar_:
		case TokenType.dchar_:
		case TokenType.bool_:
		case TokenType.byte_:
		case TokenType.ubyte_:
		case TokenType.short_:
		case TokenType.ushort_:
		case TokenType.cent_:
		case TokenType.ucent_:
		case TokenType.float_:
		case TokenType.ifloat_:
		case TokenType.cfloat_:
		case TokenType.idouble_:
		case TokenType.cdouble_:
		case TokenType.double_:
		case TokenType.real_:
		case TokenType.ireal_:
		case TokenType.creal_:
		case TokenType.identifier:
		case TokenType.rParen:
		case TokenType.rBracket:
		case TokenType.this_:
			auto visitor = processModule(tokenArray);
			auto expression = getExpression(beforeTokens[0 .. $ - 1]);
			response.setCompletions(visitor, expression, request.cursorPosition,
				CompletionType.identifiers);
			break;
		case TokenType.lParen:
		case TokenType.lBrace:
		case TokenType.lBracket:
		case TokenType.semicolon:
		case TokenType.colon:
			// TODO: global scope
			break;
		default:
			break;
		}
	}
	return response;
}

void setCompletions(T)(ref AutocompleteResponse response,
	AutocompleteVisitor visitor, T tokens, size_t cursorPosition,
	CompletionType completionType)
{
	assert (visitor.scope_);
	visitor.scope_.resolveSymbolTypes();
	ACSymbol[] symbols = visitor.scope_.findSymbolsInCurrentScope(cursorPosition, tokens[0].value);
	if (symbols.length == 0)
	{
		writeln("Could not find declaration of ", tokens[0].value);
		return;
	}

	if (completionType == CompletionType.identifiers
		&& symbols[0].kind == CompletionKind.memberVariableName
		|| symbols[0].kind == CompletionKind.variableName
		|| symbols[0].kind == CompletionKind.enumMember)
	{
		symbols = symbols[0].resolvedType is null ? [] : [symbols[0].resolvedType];
		if (symbols.length == 0)
			return;
	}

	loop: for (size_t i = 1; i < tokens.length; i++)
	{
		TokenType open;
		TokenType close;
		void skip()
		{
			i++;
			for (int depth = 1; depth > 0 && i < tokens.length; i++)
			{
				if (tokens[i].type == open)
					depth++;
				else if (tokens[i].type == close)
				{
					depth--;
					if (depth == 0) break;
				}
			}
		}
		with (TokenType) switch (tokens[i].type)
		{
		case TokenType.int_:
		case TokenType.uint_:
		case TokenType.long_:
		case TokenType.ulong_:
		case TokenType.char_:
		case TokenType.wchar_:
		case TokenType.dchar_:
		case TokenType.bool_:
		case TokenType.byte_:
		case TokenType.ubyte_:
		case TokenType.short_:
		case TokenType.ushort_:
		case TokenType.cent_:
		case TokenType.ucent_:
		case TokenType.float_:
		case TokenType.ifloat_:
		case TokenType.cfloat_:
		case TokenType.idouble_:
		case TokenType.cdouble_:
		case TokenType.double_:
		case TokenType.real_:
		case TokenType.ireal_:
		case TokenType.creal_:
		case this_:
			symbols = symbols[0].getPartsByName(getTokenValue(tokens[i].type));
			if (symbols.length == 0)
				break loop;
			break;
		case identifier:
//			stderr.writeln("looking for ", tokens[i].value, " in ", symbols[0].name);
			symbols = symbols[0].getPartsByName(tokens[i].value);
			if (symbols.length == 0)
			{
				//writeln("Couldn't find it.");
				break loop;
			}
			if (symbols[0].kind == CompletionKind.variableName
				|| symbols[0].kind == CompletionKind.memberVariableName
				|| symbols[0].kind == CompletionKind.enumMember
				|| (symbols[0].kind == CompletionKind.functionName
				&& (completionType == CompletionType.identifiers
				|| i + 1 < tokens.length)))
			{
				symbols = symbols[0].resolvedType is null ? [] :[symbols[0].resolvedType];
			}
			break;
		case lParen:
			open = TokenType.lParen;
			close = TokenType.rParen;
			skip();
			break;
		case lBracket:
			open = TokenType.lBracket;
			close = TokenType.rBracket;
			if (symbols[0].qualifier == SymbolQualifier.array)
			{
				auto h = i;
				skip();
				Parser p;
				p.setTokens(tokens[h .. i].array());
				if (!p.isSliceExpression())
				{
					symbols = symbols[0].resolvedType is null ? [] :[symbols[0].resolvedType];
				}
			}
			else if (symbols[0].qualifier == SymbolQualifier.assocArray)
			{
				symbols = symbols[0].resolvedType is null ? [] :[symbols[0].resolvedType];
				skip();
			}
			else
			{
				auto h = i;
				skip();
				Parser p;
				p.setTokens(tokens[h .. i].array());
				ACSymbol[] overloads;
				if (p.isSliceExpression())
					overloads = symbols[0].getPartsByName("opSlice");
				else
					overloads = symbols[0].getPartsByName("opIndex");
				if (overloads.length > 0)
				{
					symbols = overloads[0].resolvedType is null ? [] : [overloads[0].resolvedType];
				}
				else
					return;
			}
			break;
		case dot:
			break;
		default:
			break loop;
		}
	}

	if (symbols.length == 0)
	{
		writeln("Could not get completions");
		return;
	}
	if (completionType == CompletionType.identifiers)
	{
		foreach (s; symbols[0].parts.filter!(a => a.name !is null && a.name[0] != '*'))
		{
//			writeln("Adding ", s.name, " to the completion list");
			response.completionKinds ~= s.kind;
			response.completions ~= s.name;
		}
		response.completionType = CompletionType.identifiers;
	}
	else if (completionType == CompletionType.calltips)
	{
		if (symbols[0].kind != CompletionKind.functionName)
		{
			auto call = symbols[0].getPartsByName("opCall");
			if (call.length == 0)
			{
				symbols = call;
				goto setCallTips;
			}
			auto constructor = symbols[0].getPartsByName("*constructor*");
			if (constructor.length == 0)
				return;
			else
			{
				symbols = constructor;
				goto setCallTips;
			}
		}
	setCallTips:
		response.completionType = CompletionType.calltips;
		foreach (symbol; symbols)
		{
//			writeln("Adding calltip ", symbol.calltip);
			response.completions ~= symbol.calltip;
		}
	}

}

T getExpression(T)(T beforeTokens)
{
	size_t i = beforeTokens.length - 1;
	TokenType open;
	TokenType close;
	bool hasSpecialPrefix = false;
	expressionLoop: while (true)
	{
		with (TokenType) switch (beforeTokens[i].type)
		{
		case TokenType.int_:
		case TokenType.uint_:
		case TokenType.long_:
		case TokenType.ulong_:
		case TokenType.char_:
		case TokenType.wchar_:
		case TokenType.dchar_:
		case TokenType.bool_:
		case TokenType.byte_:
		case TokenType.ubyte_:
		case TokenType.short_:
		case TokenType.ushort_:
		case TokenType.cent_:
		case TokenType.ucent_:
		case TokenType.float_:
		case TokenType.ifloat_:
		case TokenType.cfloat_:
		case TokenType.idouble_:
		case TokenType.cdouble_:
		case TokenType.double_:
		case TokenType.real_:
		case TokenType.ireal_:
		case TokenType.creal_:
		case this_:
		case identifier:
			if (hasSpecialPrefix)
			{
				i++;
				break expressionLoop;
			}
			break;
		case dot:
			break;
		case star:
		case bitAnd:
			hasSpecialPrefix = true;
			break;
		case rParen:
			open = rParen;
			close = lParen;
			goto skip;
		case rBracket:
			open = rBracket;
			close = lBracket;
		skip:
			int depth = 1;
			do
			{
				if (depth == 0 || i == 0)
					break;
				else
					i--;
				if (beforeTokens[i].type == open)
					depth++;
				else if (beforeTokens[i].type == close)
					depth--;
			} while (true);
			break;
		default:
			if (hasSpecialPrefix)
				i++;
			i++;
			break expressionLoop;
		}
		if (i == 0)
			break;
		else
			i--;
	}
	return beforeTokens[i .. $];
}

string createCamelCaseRegex(string input)
{
	dstring output;
	uint i;
	foreach (dchar d; input)
	{
		if (isLower(d))
			output ~= d;
		else if (i > 0)
		{
			output ~= ".*";
			output ~= d;
		}
		i++;
	}
	return to!string(output ~ ".*");
}

unittest
{
	assert("ClNa".createCamelCaseRegex() == "Cl.*Na.*");
}

/**
 * Initializes builtin types and the various properties of builtin types
 */
static this()
{
	auto bool_ = new ACSymbol("bool", CompletionKind.keyword);
	auto int_ = new ACSymbol("int", CompletionKind.keyword);
	auto long_ = new ACSymbol("long", CompletionKind.keyword);
	auto byte_ = new ACSymbol("byte", CompletionKind.keyword);
	auto dchar_ = new ACSymbol("dchar", CompletionKind.keyword);
	auto short_ = new ACSymbol("short", CompletionKind.keyword);
	auto ubyte_ = new ACSymbol("ubyte", CompletionKind.keyword);
	auto uint_ = new ACSymbol("uint", CompletionKind.keyword);
	auto ulong_ = new ACSymbol("ulong", CompletionKind.keyword);
	auto ushort_ = new ACSymbol("ushort", CompletionKind.keyword);
	auto wchar_ = new ACSymbol("wchar", CompletionKind.keyword);

	auto alignof_ = new ACSymbol("alignof", CompletionKind.keyword, ulong_);
	auto mangleof_ = new ACSymbol("mangleof", CompletionKind.keyword);
	auto sizeof_ = new ACSymbol("sizeof", CompletionKind.keyword, ulong_);
	auto stringof_ = new ACSymbol("stringof", CompletionKind.keyword);

	arraySymbols ~= alignof_;
	arraySymbols ~= new ACSymbol("dup", CompletionKind.keyword);
	arraySymbols ~= new ACSymbol("idup", CompletionKind.keyword);
	arraySymbols ~= new ACSymbol("init", CompletionKind.keyword);
	arraySymbols ~= new ACSymbol("length", CompletionKind.keyword, ulong_);
	arraySymbols ~= mangleof_;
	arraySymbols ~= new ACSymbol("ptr", CompletionKind.keyword);
	arraySymbols ~= new ACSymbol("reverse", CompletionKind.keyword);
	arraySymbols ~= sizeof_;
	arraySymbols ~= new ACSymbol("sort", CompletionKind.keyword);
	arraySymbols ~= stringof_;

	assocArraySymbols ~= alignof_;
	assocArraySymbols ~= new ACSymbol("byKey", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("byValue", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("dup", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("get", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("init", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("keys", CompletionKind.keyword);
	assocArraySymbols ~= new ACSymbol("length", CompletionKind.keyword, ulong_);
	assocArraySymbols ~= mangleof_;
	assocArraySymbols ~= new ACSymbol("rehash", CompletionKind.keyword);
	assocArraySymbols ~= sizeof_;
	assocArraySymbols ~= stringof_;
	assocArraySymbols ~= new ACSymbol("values", CompletionKind.keyword);

	foreach (s; [bool_, int_, long_, byte_, dchar_, short_, ubyte_, uint_,
		ulong_, ushort_, wchar_])
	{
		s.parts ~= new ACSymbol("init", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("min", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("max", CompletionKind.keyword, s);
		s.parts ~= alignof_;
		s.parts ~= sizeof_;
		s.parts ~= stringof_;
		s.parts ~= mangleof_;
	}

	auto cdouble_ = new ACSymbol("cdouble", CompletionKind.keyword);
	auto cent_ = new ACSymbol("cent", CompletionKind.keyword);
	auto cfloat_ = new ACSymbol("cfloat", CompletionKind.keyword);
	auto char_ = new ACSymbol("char", CompletionKind.keyword);
	auto creal_ = new ACSymbol("creal", CompletionKind.keyword);
	auto double_ = new ACSymbol("double", CompletionKind.keyword);
	auto float_ = new ACSymbol("float", CompletionKind.keyword);
	auto idouble_ = new ACSymbol("idouble", CompletionKind.keyword);
	auto ifloat_ = new ACSymbol("ifloat", CompletionKind.keyword);
	auto ireal_ = new ACSymbol("ireal", CompletionKind.keyword);
	auto real_ = new ACSymbol("real", CompletionKind.keyword);
	auto ucent_ = new ACSymbol("ucent", CompletionKind.keyword);

	foreach (s; [cdouble_, cent_, cfloat_, char_, creal_, double_, float_,
		idouble_, ifloat_, ireal_, real_, ucent_])
	{
		s.parts ~= alignof_;
		s.parts ~= new ACSymbol("dig", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("episilon", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("infinity", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("init", CompletionKind.keyword, s);
		s.parts ~= mangleof_;
		s.parts ~= new ACSymbol("mant_dig", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("max", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("max_10_exp", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("max_exp", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("min", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("min_exp", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("min_10_exp", CompletionKind.keyword, int_);
		s.parts ~= new ACSymbol("min_normal", CompletionKind.keyword, s);
		s.parts ~= new ACSymbol("nan", CompletionKind.keyword, s);
		s.parts ~= sizeof_;
		s.parts ~= stringof_;
	}

	ireal_.parts ~= new ACSymbol("im", CompletionKind.keyword, real_);
	ifloat_.parts ~= new ACSymbol("im", CompletionKind.keyword, float_);
	idouble_.parts ~= new ACSymbol("im", CompletionKind.keyword, double_);
	ireal_.parts ~= new ACSymbol("re", CompletionKind.keyword, real_);
	ifloat_.parts ~= new ACSymbol("re", CompletionKind.keyword, float_);
	idouble_.parts ~= new ACSymbol("re", CompletionKind.keyword, double_);

	auto void_ = new ACSymbol("void", CompletionKind.keyword);

	builtinSymbols = [bool_, int_, long_, byte_, dchar_, short_, ubyte_, uint_,
		ulong_, ushort_, wchar_, cdouble_, cent_, cfloat_, char_, creal_, double_,
		float_, idouble_, ifloat_, ireal_, real_, ucent_, void_];
}

ACSymbol[] builtinSymbols;
ACSymbol[] arraySymbols;
ACSymbol[] assocArraySymbols;
ACSymbol[] classSymbols;
ACSymbol[] structSymbols;
