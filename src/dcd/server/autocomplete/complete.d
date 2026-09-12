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

module dcd.server.autocomplete.complete;

import std.algorithm;
import std.array;
import std.conv;
import std.experimental.allocator;
import std.experimental.logger;
import std.file;
import std.path;
import std.range : assumeSorted;
import std.string;
import std.typecons;
import std.exception : enforce;

import dcd.server.autocomplete.util;

import dparse.lexer;
import dparse.rollback_allocator;

import dsymbol.builtin.names;
import dsymbol.builtin.symbols;
import dsymbol.conversion;
import dsymbol.modulecache;
import dsymbol.scope_;
import dsymbol.string_interning;
import dsymbol.symbol;
import dsymbol.ufcs;
import dsymbol.utils;

import dcd.common.constants;
import dcd.common.messages;

enum CalltipHint {
	none, // asserts false if passed into setCompletion with CompletionType.calltips
	regularArguments,
	templateArguments,
	indexOperator,
}

/**
 * Handles autocompletion
 * Params:
 *     request = the autocompletion request
 * Returns:
 *     the autocompletion response
 */
public AutocompleteResponse complete(const AutocompleteRequest request,
	ref ModuleCache moduleCache)
{
	const(Token)[] tokenArray;
	// clampedBucketCount guards against the empty-document crash
	// (optimalBucketCount(0) == 0 is rejected by StringCache)
	auto stringCache = StringCache(clampedBucketCount(request.sourceCode.length));
	auto beforeTokens = getTokensBeforeCursor(request.sourceCode,
		request.cursorPosition, stringCache, tokenArray);
	AutocompleteResponse response;

	// `import |` - the cursor is right after the import keyword with no
	// module name typed yet. Route it to the import completion with an
	// empty partial so the available modules/packages are offered (the
	// same result as `import s|`, minus the prefix filter). This must
	// happen before the keyword faking below, which would otherwise turn
	// the trailing `import` keyword into an identifier and send the
	// request to dot completion. The keyword token itself is passed
	// through: setImportCompletions only looks at identifier tokens, so
	// it contributes neither a partial nor a module path component.
	if (beforeTokens.length && beforeTokens[$ - 1] == tok!"import")
	{
		AutocompleteResponse importResponse;
		setImportCompletions(beforeTokens[$ - 1 .. $], importResponse, moduleCache);
		return importResponse;
	}

	// `@|` - the cursor is right after an `@` (or after `@` plus a partial
	// identifier, e.g. `@no`). Offer the @-spelled attributes. This must
	// happen before the keyword faking below: `@safe` lexes as `@` +
	// keyword `safe`, and the faking would turn the trailing keyword into
	// an identifier and route the request to dot completion, where the
	// partial "safe" matches nothing.
	if (atAttributeCompletion(beforeTokens, response))
		return response;

	// allows to get completion on keyword, typically "is"
	if (beforeTokens.length &&
		(isKeyword(beforeTokens[$-1].type) || isBasicType(beforeTokens[$-1].type)))
	{
		Token* fakeIdent = cast(Token*) (&beforeTokens[$-1]);
		fakeIdent.text = str(fakeIdent.type);
		fakeIdent.type = tok!"identifier";
	}

	// `void mama() |` / `void mama() pu|` - the cursor is in the function
	// attribute position: right after a function's parameter list, where
	// attributes like `pure`, `nothrow` or `@safe` may be written. Offer
	// them instead of the (bogus) member completion on the function
	// symbol that this position would otherwise produce.
	if (isFunctionAttributePosition(beforeTokens))
	{
		string partial;
		if (beforeTokens.length && beforeTokens[$ - 1] == tok!"identifier")
		{
			auto t = beforeTokens[$ - 1];
			// A partial only when the cursor is ON the identifier (mid-word
			// or adjacent); a gap means the word is complete and the user
			// is typing the next attribute.
			if (request.cursorPosition <= t.index + t.text.length)
				partial = t.text[0 .. request.cursorPosition - t.index];
		}
		setFunctionAttributeCompletions(response, partial,
			isInsideAggregate(beforeTokens));
		return response;
	}

	const bool dotId = beforeTokens.length >= 2 &&
		beforeTokens[$-1] == tok!"identifier" && beforeTokens[$-2] == tok!".";

	// detects if the completion request uses the current module `ModuleDeclaration`
	// as access chain. In this case removes this access chain, and just keep the dot
	// because within a module semantic is the same (`myModule.stuff` -> `.stuff`).
	if (tokenArray.length >= 3 && tokenArray[0] == tok!"module" && beforeTokens.length &&
		(beforeTokens[$-1] == tok!"." || dotId))
	{
		const moduleDeclEndIndex = tokenArray.countUntil!(a => a.type == tok!";");
		bool beginsWithModuleName;
		// enough room for the module decl and the fqn...
		if (moduleDeclEndIndex != -1 && beforeTokens.length >= moduleDeclEndIndex * 2)
			foreach (immutable i; 0 .. moduleDeclEndIndex)
		{
			const expectIdt = bool(i & 1);
			const expectDot = !expectIdt;
			const j = beforeTokens.length - moduleDeclEndIndex + i - 1 - ubyte(dotId);

			// verify that the chain is well located after an expr or a decl
			if (i == 0)
			{
				if (!beforeTokens[j].type.among(tok!"{", tok!"}", tok!";",
					tok!"[", tok!"(", tok!",",  tok!":"))
						break;
			}
			// then compare the end of the "before tokens" (access chain)
			// with the firsts (ModuleDeclaration)
			else
			{
				// even index : must be a dot
				if (expectDot &&
					(tokenArray[i].type != tok!"." || beforeTokens[j].type != tok!"."))
						break;
				// odd index : identifiers must match
				else if (expectIdt &&
					(tokenArray[i].type != tok!"identifier" || beforeTokens[j].type != tok!"identifier" ||
					tokenArray[i].text != beforeTokens[j].text))
						break;
			}
			if (i == moduleDeclEndIndex - 1)
				beginsWithModuleName = true;
		}


		// replace the "before tokens" with a pattern making the remaining
		// parts of the completion process think that it's a "Module Scope Operator".
		if (beginsWithModuleName)
		{
			if (dotId)
				beforeTokens = assumeSorted([const Token(tok!"{"), const Token(tok!"."),
					cast(const) beforeTokens[$-1]]);
			else
				beforeTokens = assumeSorted([const Token(tok!"{"), const Token(tok!".")]);
		}
	}

	size_t parenIndex;
	auto calltipHint = getCalltipHint(beforeTokens, parenIndex);

	final switch (calltipHint) with (CalltipHint) {
	case regularArguments, templateArguments, indexOperator:
		return calltipCompletion(beforeTokens[0 .. parenIndex], tokenArray,
			request.cursorPosition, moduleCache, calltipHint);
	case none:
		// could be import or dot completion
		if (beforeTokens.length < 2){
			break;
		}

		ImportKind kind = determineImportKind(beforeTokens);
		if (kind == ImportKind.neither)
		{
			if (beforeTokens.isUdaExpression)
				beforeTokens = beforeTokens[$ - 1 .. $];
			return dotCompletion(beforeTokens, tokenArray, request.cursorPosition,
				moduleCache);
		}
		return importCompletion(beforeTokens, kind, moduleCache);
	}
	return dotCompletion(beforeTokens, tokenArray, request.cursorPosition, moduleCache);
}

/**
 * Handles dot completion for identifiers and types.
 * Params:
 *     beforeTokens = the tokens before the cursor
 *     tokenArray = all tokens in the file
 *     cursorPosition = the cursor position in bytes
 * Returns:
 *     the autocompletion response
 */
AutocompleteResponse dotCompletion(T)(T beforeTokens, const(Token)[] tokenArray,
	size_t cursorPosition, ref ModuleCache moduleCache)
{
	AutocompleteResponse response;

	// Partial symbol name appearing after the dot character and before the
	// cursor.
	string partial;

	// Type of the token before the dot, or identifier if the cursor was at
	// an identifier.
	IdType significantTokenType;

	if (beforeTokens.length >= 1 && beforeTokens[$ - 1] == tok!"identifier")
	{
		// Set partial to the slice of the identifier between the beginning
		// of the identifier and the cursor. This improves the completion
		// responses when the cursor is in the middle of an identifier instead
		// of at the end
		auto t = beforeTokens[$ - 1];
		if (cursorPosition - t.index >= 0 && cursorPosition - t.index <= t.text.length)
		{
			partial = t.text[0 .. cursorPosition - t.index];
			// issue 442 - prevent `partial` to start in the middle of a MBC
			// since later there's a non-nothrow call to `toUpper`
			import std.utf : validate, UTFException;
			try validate(partial);
			catch (UTFException)
			{
				import std.experimental.logger : warning;
				warning("cursor positioned within a UTF sequence");
				partial = "";
			}
		}
		significantTokenType = partial.length ? tok!"identifier" : tok!"";
		beforeTokens = beforeTokens[0 .. $ - 1];
	}
	else if (beforeTokens.length >= 2 && beforeTokens[$ - 1] == tok!".")
		significantTokenType = beforeTokens[$ - 2].type;
	else if (beforeTokens.empty || beforeTokens[$ - 1].type.among(
		tok!"{", tok!"}", tok!";", tok!":", tok!"(", tok!"[", tok!","))
	{
		// Fresh statement position with nothing typed (including the very
		// beginning of the file, e.g. the line before a declaration):
		// offer every symbol visible at the cursor. setCompletions only
		// walks the cursor scope when `partial` is non-null, so pass ""
		// (no prefix filter).
		RollbackAllocator rba;
		ScopeSymbolPair pair = generateAutocompleteTrees(tokenArray, &rba,
			cursorPosition, moduleCache);
		scope(exit) pair.destroy();
		response.setCompletions(pair.scope_, getExpression(beforeTokens),
			cursorPosition, CompletionType.identifiers, CalltipHint.none, "");
		if (!pair.ufcsSymbols.empty)
		{
			response.completions ~= pair.ufcsSymbols.map!(s =>
				makeSymbolCompletionInfo(s, CompletionKind.ufcsName)).array;
			response.completionType = CompletionType.identifiers;
		}
		// A declaration can start here (`; pure void f()`, `} @safe int x`),
		// so the declaration attributes are offered alongside the scope
		// symbols. Only for the boundaries that start declarations; `(`, `[`
		// and `,` are argument positions where attributes are invalid.
		if (beforeTokens.empty
			|| beforeTokens[$ - 1].type.among(tok!";", tok!"}", tok!"{"))
			setDeclarationAttributeCompletions(response, null);
		return response;
	}
	else
		return response;
	switch (significantTokenType)
	{
	mixin(STRING_LITERAL_CASES);
		foreach (symbol; arraySymbols)
			response.completions ~= makeSymbolCompletionInfo(symbol, symbol.kind);
		goto case;
	mixin(TYPE_IDENT_CASES);
	case tok!")":
	case tok!"]":
		RollbackAllocator rba;
		ScopeSymbolPair pair = generateAutocompleteTrees(tokenArray, &rba, cursorPosition, moduleCache);
		scope(exit) pair.destroy();
		response.setCompletions(pair.scope_, getExpression(beforeTokens),
			cursorPosition, CompletionType.identifiers, CalltipHint.none, partial);
		if (!pair.ufcsSymbols.empty) {
			response.completions ~= pair.ufcsSymbols.map!(s => makeSymbolCompletionInfo(s, CompletionKind.ufcsName)).array;
			// Setting CompletionType in case of none symbols are found via setCompletions, but we have UFCS symbols.
			response.completionType = CompletionType.identifiers;
		}
		// The built-in `.offsetof` property applies to field access
		// expressions only (e.g. `s.field.` or `Type.field.`), never to a
		// type or a plain value, so it lives in no property tree. Offer it
		// when the expression before the dot resolves to a field symbol.
		// setCompletions swaps the last chain element for its TYPE (that is
		// where alignof/sizeof come from), which loses field-ness, so
		// re-resolve the same expression with location semantics: the last
		// token is then kept as the symbol itself.
		if (partial.empty || "offsetof".startsWith(partial))
		{
			auto expression = getExpression(beforeTokens);
			// Strip the trailing dot(s): the chain resolver swaps every
			// non-final element with its type, and the dot the user just
			// typed would make the field non-final.
			size_t expressionLength = expression.length;
			while (expressionLength > 0 && expression[expressionLength - 1] == tok!".")
				expressionLength--;
			auto fieldSymbols = getSymbolsByTokenChain(pair.scope_,
				expression[0 .. expressionLength], cursorPosition,
				CompletionType.location);
			if (fieldSymbols.length > 0 && fieldSymbols[0].isAggregateField
				&& !response.completions.canFind!(a => a.identifier == "offsetof"))
			{
				response.completions ~= makeSymbolCompletionInfo(
					offsetofSymbol, offsetofSymbol.kind);
			}
		}
		// A partial identifier at a declaration start (`; pu|`, `{ pu|`,
		// `pure no|`, or the very beginning of the file): a declaration can
		// start with an attribute, so offer them alongside the scope symbols.
		if (partial.length
			&& isDeclarationAttributeStart(beforeTokens, tokenArray, partial))
			setDeclarationAttributeCompletions(response, partial);
		break;
	//  these tokens before a "." mean "Module Scope Operator"
	case tok!":":
	case tok!"(":
	case tok!"[":
	case tok!"{":
	case tok!";":
	case tok!"}":
	case tok!",":
		RollbackAllocator rba;
		ScopeSymbolPair pair = generateAutocompleteTrees(tokenArray, &rba, 1, moduleCache);
		scope(exit) pair.destroy();
		response.setCompletions(pair.scope_, getExpression(beforeTokens),
			1, CompletionType.identifiers, CalltipHint.none, partial);
		break;
	default:
		break;
	}
	return response;
}

deprecated("Use `calltipCompletion` instead") alias parenCompletion = calltipCompletion;
/**
 * Handles calltip completion for function calls and some keywords
 * Params:
 *     beforeTokens = the tokens before the cursor
 *     tokenArray = all tokens in the file
 *     cursorPosition = the cursor position in bytes
 * Returns:
 *     the autocompletion response
 */
AutocompleteResponse calltipCompletion(T)(T beforeTokens,
	const(Token)[] tokenArray, size_t cursorPosition, ref ModuleCache moduleCache,
	CalltipHint calltipHint = CalltipHint.none)
{
	AutocompleteResponse response;
	immutable(ConstantCompletion)[] completions;
	auto significantTokenId = getSignificantTokenId(beforeTokens);

	switch (significantTokenId)
	{
	case tok!"__traits":
		completions = traits;
		goto fillResponse;
	case tok!"scope":
		completions = scopes;
		goto fillResponse;
	case tok!"version":
		completions = predefinedVersions;
		goto fillResponse;
	case tok!"extern":
		completions = linkages;
		goto fillResponse;
	case tok!"pragma":
		completions = pragmas;
	fillResponse:
		response.completionType = CompletionType.identifiers;
		foreach (completion; completions)
		{
			response.completions ~= AutocompleteResponse.Completion(
				completion.identifier,
				CompletionKind.keyword,
				null, null, 0, // definition, symbol path+location
				completion.ddoc
			);
		}
		break;
	case tok!"characterLiteral":
	case tok!"doubleLiteral":
	case tok!"floatLiteral":
	case tok!"identifier":
	case tok!"idoubleLiteral":
	case tok!"ifloatLiteral":
	case tok!"intLiteral":
	case tok!"irealLiteral":
	case tok!"longLiteral":
	case tok!"realLiteral":
	case tok!"uintLiteral":
	case tok!"ulongLiteral":
	case tok!"this":
	case tok!"super":
	case tok!")":
	case tok!"]":
	mixin(STRING_LITERAL_CASES);
		RollbackAllocator rba;
		ScopeSymbolPair pair = generateAutocompleteTrees(tokenArray, &rba, cursorPosition, moduleCache);
		scope(exit) pair.destroy();
		// We remove by 2 when the calltip hint is !( else remove by 1.
		auto endOffset = beforeTokens.isTemplateBangParen ? 2 : 1;
		auto expression = getExpression(beforeTokens[0 .. $ - endOffset]);
		response.setCompletions(pair.scope_, expression,
			cursorPosition, CompletionType.calltips, calltipHint);
		if (!pair.ufcsSymbols.empty) {
			response.completions ~= pair.ufcsSymbols.map!(s => makeSymbolCompletionInfo(s, CompletionKind.ufcsName)).array;
			// Setting CompletionType in case of none symbols are found via setCompletions, but we have UFCS symbols.
			response.completionType = CompletionType.calltips;
		}
		break;
	default:
		break;
	}
	return response;
}

IdType getSignificantTokenId(T)(T beforeTokens)
{
	auto significantTokenId = beforeTokens[$ - 2].type;
	if (beforeTokens.isTemplateBangParen)
	{
		return beforeTokens[$ - 3].type;
	}
	return significantTokenId;
}
/**
 * Hinting what the user expects for calltip completion
 * Params:
 *   beforeTokens = tokens before the cursor
 * Returns: calltipHint based of beforeTokens
 */
CalltipHint getCalltipHint(T)(T beforeTokens, out size_t parenIndex)
{
	if (beforeTokens.length < 2)
	{
		return CalltipHint.none;
	}

	parenIndex = beforeTokens.length;
	// evaluate at comma case
	if (beforeTokens.isComma)
	{
		// A comma inside a selective import (`import std.math: abs, `)
		// separates import binds, not call arguments, the calltip walk
		// below would scan back past the `:` and resolve the module name
		// as an expression, yielding no completions. Import completion
		// must handle it instead.
		if (determineImportKind(beforeTokens) != ImportKind.neither)
			return CalltipHint.none;

		size_t tmp = beforeTokens.goBackToOpenParen;
		if(tmp == size_t.max){
			return CalltipHint.regularArguments;
		}
		parenIndex = tmp;

		// check if we are actually a "!("
		if (beforeTokens[0 .. parenIndex].isTemplateBangParen)
		{
			return CalltipHint.templateArguments;
		}
		else if (beforeTokens[0 .. parenIndex].isIndexOperator)
		{
			// we are inside `a[foo, bar]`, which is definitely a custom opIndex
			return CalltipHint.indexOperator;
		}
		return CalltipHint.regularArguments;
	}

	if (beforeTokens.isIndexOperator)
	{
		return CalltipHint.indexOperator;
	}
	else if (beforeTokens.isTemplateBang || beforeTokens.isTemplateBangParen)
	{
		return CalltipHint.templateArguments;
	}
	else if (beforeTokens.isOpenParen || beforeTokens.isOpenSquareBracket)
	{
		// open square bracket for literals: `foo([`
		return CalltipHint.regularArguments;
	}

	return CalltipHint.none;
}

/**
 * Fills the response with the @-spelled attributes matching the partial
 * identifier typed after an `@` (e.g. `@no` -> `@nogc`).
 *
 * Params:
 *     partial = the partial identifier typed after the `@`, or null
 *     response = the response to fill
 */
private void setAtAttributeCompletions(ref AutocompleteResponse response, string partial)
{
	response.completionType = CompletionType.identifiers;
	foreach (completion; atAttributes)
	{
		if (partial is null || completion.identifier[1 .. $].startsWith(partial))
			response.completions ~= AutocompleteResponse.Completion(
				completion.identifier,
				CompletionKind.keyword,
				null, null, 0, // definition, symbol path+location
				completion.ddoc
			);
	}
}

/**
 * Completion for the @-spelled function attributes (`@nogc`, `@safe`, ...).
 *
 * Matches when the token before the cursor is an `@` (nothing typed yet:
 * `@|`) or an identifier/keyword directly following an `@` (a partial:
 * `@no|`). Fills `response` and returns true in those cases; returns false
 * otherwise (leaving `response` untouched).
 *
 * The plain (non-@) attributes like `pure`, `ref`, `scope` are NOT handled
 * here: they are ordinary keywords, so the regular scope completion already
 * offers them wherever they are valid D.
 */
private bool atAttributeCompletion(T)(T beforeTokens,
	ref AutocompleteResponse response)
{
	if (beforeTokens.empty)
		return false;

	// `@|` - nothing typed after the @ yet
	if (beforeTokens[$ - 1] == tok!"@")
	{
		setAtAttributeCompletions(response, null);
		return true;
	}

	// `@par|` - a partial identifier (or keyword, e.g. `@saf|`) after the @
	if (beforeTokens.length >= 2 && beforeTokens[$ - 2] == tok!"@"
		&& (beforeTokens[$ - 1] == tok!"identifier" || isKeyword(beforeTokens[$ - 1].type)))
	{
		// A COMPLETE attribute (`@safe`) is already typed, not a partial:
		// fall through so the function-attribute position logic below can
		// offer every attribute (the user may type more after it).
		if (atAttributes.canFind!(a => a.identifier[1 .. $] == beforeTokens[$ - 1].text))
			return false;
		setAtAttributeCompletions(response, beforeTokens[$ - 1].text);
		return true;
	}

	return false;
}

/**
 * Fills the response with the function attributes valid after a
 * parameter list (`pure`, `nothrow`, `@safe`, ...), filtered by the
 * partial identifier the user typed (if any).
 *
 * The @-spelled attributes are matched against their name without the
 * `@` so that typing `no` finds both `nothrow` and `@nogc`.
 */
private void setFunctionAttributeCompletions(ref AutocompleteResponse response,
	string partial, bool isMethod)
{
	response.completionType = CompletionType.identifiers;
	foreach (completion; functionAttributes)
	{
		if (partial is null || completion.identifier.startsWith(partial))
			response.completions ~= AutocompleteResponse.Completion(
				completion.identifier,
				CompletionKind.keyword,
				null, null, 0, // definition, symbol path+location
				completion.ddoc
			);
	}
	// `const`/`immutable`/`inout`/`shared` are only valid on methods -
	// a free function cannot be `const`.
	if (isMethod)
	{
		foreach (completion; methodAttributes)
		{
			if (partial is null || completion.identifier.startsWith(partial))
				response.completions ~= AutocompleteResponse.Completion(
					completion.identifier,
					CompletionKind.keyword,
					null, null, 0, // definition, symbol path+location
					completion.ddoc
				);
		}
	}
	foreach (completion; atAttributes)
	{
		if (partial is null || completion.identifier[1 .. $].startsWith(partial))
			response.completions ~= AutocompleteResponse.Completion(
				completion.identifier,
				CompletionKind.keyword,
				null, null, 0, // definition, symbol path+location
				completion.ddoc
			);
	}
}

/**
 * Fills the response with the attributes that can START a declaration
 * (`pure`, `static`, `@safe`, ...), filtered by the partial identifier
 * the user typed (if any).
 *
 * The @-spelled attributes are matched against their name without the
 * `@` so that typing `no` finds both `nothrow` and `@nogc`.
 */
private void setDeclarationAttributeCompletions(ref AutocompleteResponse response,
	string partial)
{
	foreach (completion; declarationAttributes)
	{
		if (partial is null || completion.identifier.startsWith(partial))
			response.completions ~= AutocompleteResponse.Completion(
				completion.identifier,
				CompletionKind.keyword,
				null, null, 0, // definition, symbol path+location
				completion.ddoc
			);
	}
	foreach (completion; atAttributes)
	{
		if (partial is null || completion.identifier[1 .. $].startsWith(partial))
			response.completions ~= AutocompleteResponse.Completion(
				completion.identifier,
				CompletionKind.keyword,
				null, null, 0, // definition, symbol path+location
				completion.ddoc
			);
	}
}

/**
 * Whether `beforeTokens` (the tokens before a partial identifier that
 * was already popped) ends at a position where a declaration - and
 * therefore a declaration attribute - can start: after `;`, `{`, `}`,
 * after another attribute keyword, after a known `@`-attribute, or at
 * the very beginning of the file.
 *
 * `tokenArray` and `partial` distinguish the true beginning of the file
 * from the UDA-expression trimming in `complete()`: after `@UDA F|` the
 * popped tokens are empty too, but the file does not start with `F`.
 */
private bool isDeclarationAttributeStart(T)(T beforeTokens,
	const(Token)[] tokenArray, string partial)
{
	if (beforeTokens.empty)
	{
		return tokenArray.length > 0 && tokenArray[0] == tok!"identifier"
			&& tokenArray[0].text == partial;
	}
	// `@safe pu|` - a known @-attribute (a user-defined UDA like `@UDA F`
	// is a declaration name instead, and must not match)
	if (beforeTokens.length >= 2 && beforeTokens[$ - 2] == tok!"@"
		&& beforeTokens[$ - 1] == tok!"identifier")
	{
		switch (beforeTokens[$ - 1].text)
		{
		case "safe": case "nogc": case "trusted": case "system":
		case "property": case "disable": case "live":
			return true;
		default:
			return false;
		}
	}
	switch (beforeTokens[$ - 1].type)
	{
	case tok!";":
	case tok!"{":
	case tok!"}":
		return true;
	// Attributes stack: `pure nothrow void f()`.
	case tok!"abstract":
	case tok!"auto":
	case tok!"const":
	case tok!"final":
	case tok!"immutable":
	case tok!"inout":
	case tok!"nothrow":
	case tok!"override":
	case tok!"pure":
	case tok!"ref":
	case tok!"scope":
	case tok!"shared":
	case tok!"static":
	case tok!"synchronized":
	case tok!"__gshared":
		return true;
	default:
		return false;
	}
}

/**
 * Whether the cursor sits in a function attribute position: after the
 * parameter list of a function declaration (`void foo() | {`), possibly
 * with a partial identifier (`void foo() pu|`) or already-typed
 * attributes (`void foo() pure no|`) between the `)` and the cursor.
 *
 * The check walks back from the cursor over any attributes already
 * typed, matches the `)` to its `(`, and requires the token before the
 * `(` to be the function's name and the token before THAT to be part of
 * a declaration (a type or another attribute). This excludes call
 * expressions (`= foo() |`, `foo() |;`), where the name is preceded by
 * `=`, `(`, `;`, `{`, `.` etc.
 */
private bool isFunctionAttributePosition(T)(T beforeTokens)
{
	if (beforeTokens.empty)
		return false;

	// The partial identifier being typed, if any.
	size_t end = beforeTokens.length;
	if (beforeTokens[end - 1] == tok!"identifier")
		end--;

	// Walk back over attributes the user may already have typed so that
	// `void foo() pure no|` and `void foo() @safe |` are still recognized.
	while (end > 0)
	{
		if (beforeTokens[end - 1] == tok!"@")
			end--; // the `@` of an attribute whose name was consumed above
		else if (end >= 2 && beforeTokens[end - 2] == tok!"@")
			end -= 2; // `@` and the identifier it introduces
		else if (beforeTokens[end - 1].type.among(tok!"const", tok!"immutable",
			tok!"inout", tok!"nothrow", tok!"pure", tok!"ref", tok!"return",
			tok!"scope", tok!"shared"))
			end--;
		else
			break;
	}

	// The parameter list must end here.
	if (end == 0 || beforeTokens[end - 1] != tok!")")
		return false;

	// Match the `)` back to its `(` and skip template parameter lists
	// (`void foo(T)()`): the name sits before the outermost `(`.
	size_t nameEnd = end;
	while (nameEnd > 0 && beforeTokens[nameEnd - 1] == tok!")")
	{
		immutable open = skipParenReverse(beforeTokens[0 .. nameEnd],
			nameEnd - 1, tok!")", tok!"(");
		if (open == 0)
			return false;
		nameEnd = open;
	}
	if (nameEnd == 0)
		return false;

	// The token before the `(` is the declared name.
	const name = beforeTokens[nameEnd - 1];
	if (name != tok!"identifier" && name != tok!"this")
		return false;

	if (nameEnd < 2)
		return false;
	const before = beforeTokens[nameEnd - 2];
	if (name == tok!"this")
	{
		// Constructors and destructors are preceded by a scope boundary
		// or a type (delegating constructor calls are indistinguishable
		// lexically; suggesting attributes there is harmless).
		return before.type.among(tok!"{", tok!"}", tok!";", tok!":", tok!"~")
			|| before == tok!"identifier" || isBasicType(before.type);
	}
	// A declaration has a return type (or another attribute) before the
	// name; a call expression has `=`, `(`, `;`, `{`, `.`, `!` ... instead.
	return before == tok!"identifier" || isBasicType(before.type)
		|| before.type.among(tok!"*", tok!"]", tok!"auto", tok!"static",
			tok!"pure", tok!"nothrow", tok!"const", tok!"immutable",
			tok!"shared", tok!"inout", tok!"ref", tok!"scope",
			tok!"synchronized", tok!"override", tok!"final", tok!"abstract");
}

/**
 * Whether the tokens end inside a struct/class/interface body, i.e. the
 * enclosing `{` (found by brace matching from the end) is preceded by one
 * of the aggregate keywords. Used to offer the method-only function
 * attributes (`const`, `immutable`, `inout`, `shared`) there - a free
 * function cannot be `const`.
 */
private bool isInsideAggregate(T)(T beforeTokens)
{
	// Match braces from the end: every `}` closes a `{`, the first
	// unmatched `{` is the innermost enclosing block.
	int depth = 0;
	for (size_t i = beforeTokens.length; i > 0; i--)
	{
		const tokType = beforeTokens[i - 1].type;
		if (tokType == tok!"}")
			depth++;
		else if (tokType == tok!"{")
		{
			if (depth == 0)
			{
				// Walk left from the `{` over the aggregate's name and
				// template parameter list: `struct S {`, `class C(T) {`,
				// anonymous `union {`.
				size_t j = i - 1; // index of the `{`
				if (j > 0 && beforeTokens[j - 1] == tok!")")
				{
					immutable open = skipParenReverse(beforeTokens[0 .. j],
						j - 1, tok!")", tok!"(");
					j = open;
				}
				if (j > 0 && beforeTokens[j - 1] == tok!"identifier")
					j--; // the aggregate's name
				return j > 0 && beforeTokens[j - 1].type.among(
					tok!"struct", tok!"class", tok!"interface", tok!"union");
			}
			depth--;
		}
	}
	return false;
}

/**
 * Provides autocomplete for selective imports, e.g.:
 * ---
 * import std.algorithm: balancedParens;
 * ---
 */
AutocompleteResponse importCompletion(T)(T beforeTokens, ImportKind kind,
	ref ModuleCache moduleCache)
in
{
	assert (beforeTokens.length >= 2);
}
do
{
	AutocompleteResponse response;
	// The selective-import branch below needs at least "import x:" to build a
	// module path, but the normal branch only scans back to the "import"
	// keyword, which is safe for any token count (e.g. "import h").
	if (beforeTokens.length <= 2 && kind != ImportKind.normal)
		return response;

	size_t i = beforeTokens.length - 1;

	if (kind == ImportKind.normal)
	{

		while (beforeTokens[i].type != tok!"," && beforeTokens[i].type != tok!"import"
				&& beforeTokens[i].type != tok!"=" )
			i--;
		setImportCompletions(beforeTokens[i .. $], response, moduleCache);
		return response;
	}

	loop: while (true) switch (beforeTokens[i].type)
	{
	case tok!"identifier":
	case tok!"=":
	case tok!",":
	case tok!".":
		i--;
		break;
	case tok!":":
		i--;
		while (beforeTokens[i].type == tok!"identifier" || beforeTokens[i].type == tok!".")
			i--;
		break loop;
	default:
		break loop;
	}

	size_t j = i;
	loop2: while (j <= beforeTokens.length) switch (beforeTokens[j].type)
	{
	case tok!":": break loop2;
	default: j++; break;
	}

	if (i >= j)
	{
		warning("Malformed import statement");
		return response;
	}

	immutable string path = beforeTokens[i + 1 .. j]
		.filter!(token => token.type == tok!"identifier")
		.map!(token => cast() token.text)
		.joiner(dirSeparator)
		.text();

	string resolvedLocation = moduleCache.resolveImportLocation(path);
	if (resolvedLocation is null)
	{
		warning("Could not resolve location of ", path);
		return response;
	}
	auto symbols = moduleCache.getModuleSymbol(internString(resolvedLocation));

	import containers.hashset : HashSet;
	HashSet!string h;

	void addSymbolToResponses(const(DSymbol)* sy)
	{
		auto a = DSymbol(sy.name);
		if (!builtinSymbols.contains(&a) && sy.name !is null && !h.contains(sy.name)
				&& !sy.skipOver && sy.name != CONSTRUCTOR_SYMBOL_NAME
				&& isPublicCompletionKind(sy.kind))
		{
			response.completions ~= makeSymbolCompletionInfo(sy, sy.kind);
			h.insert(sy.name);
		}
	}

	foreach (s; symbols.opSlice().filter!(a => !a.skipOver))
	{
		if (s.kind == CompletionKind.importSymbol && s.type !is null)
			foreach (sy; s.type.opSlice().filter!(a => !a.skipOver))
				addSymbolToResponses(sy);
		else
			addSymbolToResponses(s);
	}
	response.completionType = CompletionType.identifiers;
	return response;
}

/**
 * Populates the response with completion information for an import statement
 * Params:
 *     tokens = the tokens after the "import" keyword and before the cursor
 *     response = the response that should be populated
 */
void setImportCompletions(T)(T tokens, ref AutocompleteResponse response,
	ref ModuleCache cache)
{
	response.completionType = CompletionType.identifiers;
	string partial = null;
	if (tokens[$ - 1].type == tok!"identifier")
	{
		partial = tokens[$ - 1].text;
		tokens = tokens[0 .. $ - 1];
	}
	auto moduleParts = tokens.filter!(a => a.type == tok!"identifier").map!("a.text").array();
	string path = buildPath(moduleParts);

	bool found = false;

	foreach (importPath; cache.getImportPaths())
	{
		if (importPath.isFile)
		{
			if (!exists(importPath))
				continue;

			found = true;

			auto n = importPath.baseName(".d").baseName(".di");
			if (isFile(importPath) && (importPath.endsWith(".d") || importPath.endsWith(".di"))
					&& (partial is null || n.startsWith(partial)))
				response.completions ~= AutocompleteResponse.Completion(n, CompletionKind.moduleName, null, importPath, 0);
		}
		else
		{
			string p = buildPath(importPath, path);
			if (!exists(p))
				continue;

			found = true;

			try foreach (string name; dirEntries(p, SpanMode.shallow))
			{
				import std.path: baseName;
				if (name.baseName.startsWith(".#"))
					continue;

				auto n = name.baseName(".d").baseName(".di");
				if (isFile(name) && (name.endsWith(".d") || name.endsWith(".di"))
					&& (partial is null || n.startsWith(partial)))
					response.completions ~= AutocompleteResponse.Completion(n, CompletionKind.moduleName, null, name, 0);
				else if (isDir(name))
				{
					if (n[0] != '.' && (partial is null || n.startsWith(partial)))
					{
						immutable packageDPath = buildPath(name, "package.d");
						immutable packageDIPath = buildPath(name, "package.di");
						immutable packageD = exists(packageDPath);
						immutable packageDI = exists(packageDIPath);
						immutable kind = packageD || packageDI ? CompletionKind.moduleName : CompletionKind.packageName;
						immutable file = packageD ? packageDPath : packageDI ? packageDIPath : name;
						response.completions ~= AutocompleteResponse.Completion(n, kind, null, file, 0);
					}
				}
			}
			catch(FileException)
			{
				warning("Cannot access import path: ", importPath);
			}
		}
	}
	if (!found)
		warning("Could not find ", moduleParts);
}

/**
 *
 */
void setCompletions(T)(ref AutocompleteResponse response,
	Scope* completionScope, T tokens, size_t cursorPosition,
	CompletionType completionType, CalltipHint callTipHint = CalltipHint.none,
	string partial = null)
{
	static void addSymToResponse(const(DSymbol)* s, ref AutocompleteResponse r, string p,
		Scope* completionScope, size_t[] circularGuard = [])
	{
		if (circularGuard.canFind(cast(size_t) s))
			return;
		foreach (sym; s.opSlice())
		{
			if (sym.name !is null && sym.name.length > 0 && isPublicCompletionKind(sym.kind)
				&& (p is null ? true : toUpper(sym.name.data).startsWith(toUpper(p)))
				&& !r.completions.canFind!(a => a.identifier == sym.name)
				&& sym.name[0] != '*'
				&& mightBeRelevantInCompletionScope(sym, completionScope))
			{
				r.completions ~= makeSymbolCompletionInfo(sym, sym.kind);
			}
			if (sym.kind == CompletionKind.importSymbol && !sym.skipOver && sym.type !is null)
				addSymToResponse(sym.type, r, p, completionScope, circularGuard ~ (cast(size_t) s));
		}
	}

	// Handle the simple case where we get all symbols in scope and filter it
	// based on the currently entered text.
	if (partial !is null && tokens.length == 0)
	{
		auto currentSymbols = completionScope.getSymbolsInCursorScope(cursorPosition);
		foreach (s; currentSymbols.filter!(a => isPublicCompletionKind(a.kind)
				&& toUpper(a.name.data).startsWith(toUpper(partial))
				&& mightBeRelevantInCompletionScope(a, completionScope)))
		{
			response.completions ~= makeSymbolCompletionInfo(s, s.kind);
		}
		response.completionType = CompletionType.identifiers;
		return;
	}
	// "Module Scope Operator" : filter module decls
	else if (tokens.length == 1 && tokens[0] == tok!".")
	{
		auto currentSymbols = completionScope.getSymbolsInCursorScope(cursorPosition);
		foreach (s; currentSymbols.filter!(a => isPublicCompletionKind(a.kind)
				// TODO: for now since "module.partial" is transformed into ".partial"
				// we cant put the imported symbols that should be in the list.
				&& a.kind != CompletionKind.importSymbol
				&& a.kind != CompletionKind.dummy
				&& a.symbolFile == "stdin"
				&& (partial !is null && toUpper(a.name.data).startsWith(toUpper(partial))
					|| partial is null)
				&& mightBeRelevantInCompletionScope(a, completionScope)))
		{
			response.completions ~= makeSymbolCompletionInfo(s, s.kind);
		}
		response.completionType = CompletionType.identifiers;
		return;
	}

	if (tokens.length == 0)
		return;

	DSymbol*[] symbols = getSymbolsByTokenChain(completionScope, tokens,
		cursorPosition, completionType);

	// If calltipHint is templateArguments we ensure that the symbol is also templated
	if (callTipHint == CalltipHint.templateArguments
		&& symbols.length >= 1
		&& symbols[0].qualifier != SymbolQualifier.templated)
	{
		return;
	}

	if (symbols.length == 0)
		return;

	if (completionType == CompletionType.identifiers)
	{
		while (symbols[0].qualifier == SymbolQualifier.func
				|| symbols[0].kind == CompletionKind.functionName
				|| symbols[0].kind == CompletionKind.importSymbol
				|| symbols[0].kind == CompletionKind.aliasName)
		{
			symbols = symbols[0].type is null || symbols[0].type is symbols[0] ? []
				: [symbols[0].type];
			if (symbols.length == 0)
				return;
		}
		addSymToResponse(symbols[0], response, partial, completionScope);
		response.completionType = CompletionType.identifiers;
	}
	else if (completionType == CompletionType.calltips)
	{
		enforce(callTipHint != CalltipHint.none, "Make sure to have a properly defined calltipHint!");
		//trace("Showing call tips for ", symbols[0].name, " of kind ", symbols[0].kind);
		if (symbols[0].kind != CompletionKind.functionName
			&& symbols[0].callTip is null)
		{
			if (symbols[0].kind == CompletionKind.aliasName)
			{
				if (symbols[0].type is null || symbols[0].type is symbols[0])
					return;
				symbols = [symbols[0].type];
			}
			if (symbols[0].kind == CompletionKind.variableName)
			{
				auto dumb = symbols[0].type;
				if (dumb !is null)
				{
					if (dumb.kind == CompletionKind.functionName)
					{
						symbols = [dumb];
						goto setCallTips;
					}
					if (callTipHint == CalltipHint.indexOperator)
					{
						auto index = dumb.getPartsByName(internString("opIndex"));
						if (index.length > 0)
						{
							symbols = index;
							goto setCallTips;
						}
					}
					auto call = dumb.getPartsByName(internString("opCall"));
					if (call.length > 0)
					{
						symbols = call;
						goto setCallTips;
					}
				}
			}
			if (symbols[0].kind == CompletionKind.structName
				|| symbols[0].kind == CompletionKind.className)
			{
				if (callTipHint == CalltipHint.templateArguments)
				{
					response.completionType = CompletionType.calltips;
					response.completions = [generateStructConstructorCalltip(symbols[0], callTipHint)];
					return;
				}

				//Else we do calltip for regular arguments
				auto constructor = symbols[0].getPartsByName(CONSTRUCTOR_SYMBOL_NAME);
				if (constructor.length == 0)
				{
					// Build a call tip out of the struct fields
					if (symbols[0].kind == CompletionKind.structName)
					{
						response.completionType = CompletionType.calltips;
						response.completions = [generateStructConstructorCalltip(symbols[0], callTipHint)];
						return;
					}
				}
				else
				{
					symbols = constructor;
					goto setCallTips;
				}
			}
		}
	setCallTips:
		response.completionType = CompletionType.calltips;
		foreach (symbol; symbols)
		{
			if (symbol.kind != CompletionKind.aliasName && symbol.callTip !is null)
			{
				auto completion = makeSymbolCompletionInfo(symbol, char.init);
				// TODO: put return type
				response.completions ~= completion;
			}
		}
	}
}

bool mightBeRelevantInCompletionScope(const DSymbol* symbol, Scope* scope_)
{
	import dparse.lexer : tok;

	if (symbol.protection == tok!"private" &&
		!scope_.hasSymbolRecursive(symbol))
	{
		// scope is the scope of the current file so if the symbol is not in there, it's not accessible
		return false;
	}

	return true;
}


AutocompleteResponse.Completion generateStructConstructorCalltip(
	const DSymbol* symbol,
	CalltipHint calltipHint = CalltipHint.regularArguments
)
in
{
	if (calltipHint == CalltipHint.regularArguments)
	{
		assert(symbol.kind == CompletionKind.structName);
	}
}
do
{
	string generatedStructConstructorCalltip = calltipHint == CalltipHint.regularArguments ? "this(" : symbol.name ~ "!(";
	auto completionKindFilter = calltipHint == CalltipHint.regularArguments ? CompletionKind.variableName : CompletionKind.typeTmpParam;
	const(DSymbol)*[] fields =
	symbol.opSlice().filter!(a => a.kind == completionKindFilter).map!(a => cast(const(DSymbol)*) a).array();
	// Only instance fields make up the implicit constructor's parameters.
	// static, __gshared, and enum members have no per-instance storage,
	// so they are excluded from the generated call tip.
	if (calltipHint == CalltipHint.regularArguments)
		fields = fields.filter!(a => a.isAggregateField).array();
	fields.sort!((a, b) => a.location < b.location);
	foreach (i, field; fields)
	{
		if (field.kind != completionKindFilter)
			continue;
		i++;
		if (field.type !is null && calltipHint == CalltipHint.regularArguments)
		{
			generatedStructConstructorCalltip ~= field.type.name;
			generatedStructConstructorCalltip ~= " ";
		}
		generatedStructConstructorCalltip ~= field.name;
		if (i < fields.length)
			generatedStructConstructorCalltip ~= ", ";
	}
	generatedStructConstructorCalltip ~= ")";
	auto completion = makeSymbolCompletionInfo(symbol, char.init);
	completion.identifier = calltipHint == CalltipHint.regularArguments ? "this" : symbol.name;
	completion.definition = generatedStructConstructorCalltip;
	completion.typeOf = symbol.name;
	return completion;
}
