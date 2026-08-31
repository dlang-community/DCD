module dsymbol.utils;
import dparse.lexer : tok, IdType, Token;
import dsymbol.symbol : CompletionKind, DSymbol, SymbolQualifier;
import dsymbol.string_interning : internString;
import std.algorithm.searching : canFind, startsWith;
import std.range : empty;
import std.string : stripLeft, stripRight;

enum TYPE_IDENT_CASES = q{
	case tok!"int":
	case tok!"uint":
	case tok!"long":
	case tok!"ulong":
	case tok!"char":
	case tok!"wchar":
	case tok!"dchar":
	case tok!"bool":
	case tok!"byte":
	case tok!"ubyte":
	case tok!"short":
	case tok!"ushort":
	case tok!"cent":
	case tok!"ucent":
	case tok!"float":
	case tok!"ifloat":
	case tok!"cfloat":
	case tok!"idouble":
	case tok!"cdouble":
	case tok!"double":
	case tok!"real":
	case tok!"ireal":
	case tok!"creal":
	case tok!"this":
	case tok!"super":
	case tok!"identifier":
};

enum STRING_LITERAL_CASES = q{
	case tok!"stringLiteral":
	case tok!"wstringLiteral":
	case tok!"dstringLiteral":
};

enum TYPE_IDENT_AND_LITERAL_CASES = TYPE_IDENT_CASES ~ STRING_LITERAL_CASES;

/**
 * Skips blocks of parentheses until the starting block has been closed
 */
void skipParen(T)(T tokenSlice, ref size_t i, IdType open, IdType close)
{
	if (i >= tokenSlice.length || tokenSlice.length <= 0)
		return;
	int depth = 1;
	while (depth != 0 && i + 1 != tokenSlice.length)
	{
		i++;
		if (tokenSlice[i].type == open)
			depth++;
		else if (tokenSlice[i].type == close)
			depth--;
	}
}


/**
 * Skips blocks of parentheses in reverse until the starting block has been opened
 */
size_t skipParenReverse(T)(T beforeTokens, size_t i, IdType open, IdType close)
{
	if (i == 0)
		return 0;
	int depth = 1;
	while (depth != 0 && i != 0)
	{
		i--;
		if (beforeTokens[i].type == open)
			depth++;
		else if (beforeTokens[i].type == close)
			depth--;
	}
	return i;
}



size_t skipParenReverseBefore(T)(T beforeTokens, size_t i, IdType open, IdType close)
{
	i = skipParenReverse(beforeTokens, i, open, close);
	if (i != 0)
		i--;
	return i;
}


/**
 * Traverses a token slice in reverse to find the opening parentheses or square bracket
 * that begins the block the last token is in.
 */
size_t goBackToOpenParen(T)(T beforeTokens)
in
{
	assert (beforeTokens.length > 0);
}
do
{
	size_t i = beforeTokens.length - 1;
	while (true) switch (beforeTokens[i].type)
	{
	case tok!",":
	case tok!".":
	case tok!"*":
	case tok!"&":
	case tok!"doubleLiteral":
	case tok!"floatLiteral":
	case tok!"idoubleLiteral":
	case tok!"ifloatLiteral":
	case tok!"intLiteral":
	case tok!"longLiteral":
	case tok!"realLiteral":
	case tok!"irealLiteral":
	case tok!"uintLiteral":
	case tok!"ulongLiteral":
	case tok!"characterLiteral":
	mixin(TYPE_IDENT_AND_LITERAL_CASES);
		if (i == 0)
			return size_t.max;
		else
			i--;
		break;
	case tok!"(":
	case tok!"[":
		return i + 1;
	case tok!")":
		i = beforeTokens.skipParenReverseBefore(i, tok!")", tok!"(");
		break;
	case tok!"}":
		i = beforeTokens.skipParenReverseBefore(i, tok!"}", tok!"{");
		break;
	case tok!"]":
		i = beforeTokens.skipParenReverseBefore(i, tok!"]", tok!"[");
		break;
	default:
		return size_t.max;
	}
}

///Testing skipping
unittest
{
	Token[] t = [
		Token(tok!"identifier"), Token(tok!"identifier"), Token(tok!"("),
		Token(tok!"identifier"), Token(tok!"("), Token(tok!")"), Token(tok!",")
	];
	size_t i = t.length - 1;
	i = skipParenReverse(t, i, tok!")", tok!"(");
	assert(i == 2);
	i = t.length - 1;
	i = skipParenReverseBefore(t, i, tok!")", tok!"(");
	assert(i == 1);
}

/// End-to-end: FirstPass must capture constraintText for constrained
/// function templates, and matchConstraint must use it.
unittest
{
	import dparse.ast : Module;
	import dparse.lexer : getTokensForParser, LexerConfig, StringCache,
		optimalBucketCount;
	import dparse.parser : parseModule;
	import dparse.rollback_allocator : RollbackAllocator;
	import dsymbol.conversion.first : FirstPass;
	import dsymbol.modulecache : ModuleCache;
	import dsymbol.string_interning : internString, istring;
	import std.conv : to;
	import std.string : representation;

	enum source =
		"void destroy(bool initialize = true, T)(ref T obj) if (is(T == struct)) {}\n" ~
		"void destroy(bool initialize = true, T)(T obj) if (is(T == class)) {}\n";

	LexerConfig config;
	config.fileName = "test.d";
	auto cache = StringCache(source.length.optimalBucketCount);
	auto tokens = getTokensForParser(source.dup.representation, config, &cache);
	RollbackAllocator rba;
	Module m = parseModule(tokens, "test.d", &rba);

	ModuleCache moduleCache;
	scope first = new FirstPass(m, internString("test.d"), &moduleCache);
	first.run();

	// collect all destroy symbols from the root
	DSymbol*[] destroys;
	foreach (child; first.rootSymbol.acSymbol.opSlice())
		if (child.name == "destroy")
			destroys ~= child;
	assert(destroys.length == 2, destroys.length.to!string);

	// both overloads must carry their constraint text
	assert(destroys[0].constraintText == "is(T == struct)",
		destroys[0].constraintText is null ? "null" : destroys[0].constraintText);
	assert(destroys[1].constraintText == "is(T == class)",
		destroys[1].constraintText is null ? "null" : destroys[1].constraintText);

	// and the matcher must rank them against a struct type
	DSymbol structType = DSymbol("Mama", CompletionKind.structName);
	assert(matchConstraint(destroys[0], &structType) == ConstraintMatch.match);
	assert(matchConstraint(destroys[1], &structType) == ConstraintMatch.noMatch);
}

/**
 * The result of matching a template constraint against a concrete type.
 */
enum ConstraintMatch
{
	/// The symbol has no constraint (or an unrecognized one): no opinion.
	unknown,
	/// The constraint is satisfied by the type.
	match,
	/// The constraint is provably NOT satisfied by the type.
	noMatch,
}

/**
 * Matches a template constraint of the `is(T == X)` family against the kind
 * of a concrete type.
 *
 * DCD does not evaluate template constraints (that would require full
 * instantiation), but the constrained overloads that clutter completions —
 * druntime's `destroy`, `hashOf`, etc. — almost all use this simple form,
 * where the type's kind alone decides the outcome:
 *
 * | Constraint                    | Matches when the type is... |
 * |-------------------------------|-----------------------------|
 * | `is(T == struct)`             | a struct                    |
 * | `is(T == class)`              | a class                     |
 * | `is(T == interface)`          | an interface                |
 * | `is(T == union)`              | a union                     |
 * | `is(T == enum)`               | an enum                     |
 * | `__traits(isStaticArray, T)`  | a static array              |
 * | negations of the above        | inverted                    |
 *
 * Anything else (e.g. `isInputRange!R`) returns `unknown` so callers keep
 * the overload instead of hiding it on a wrong guess.
 *
 * Params:
 *     symbol = the function symbol whose constraint is inspected
 *     type = the concrete type the overload is being matched against
 *     templateParamName = the name of the template parameter the constraint
 *         constrains (e.g. `"T"`); when empty, the first parameter of the
 *         function is assumed
 */
ConstraintMatch matchConstraint(const(DSymbol)* symbol, const(DSymbol)* type,
	string templateParamName = null)
{
	if (symbol is null || type is null)
		return ConstraintMatch.unknown;
	auto constraint = symbol.constraintText;
	if (constraint is null || constraint.empty)
		return ConstraintMatch.unknown;

	// The template parameter the constraint talks about. For UFCS-style
	// overloads like destroy(T)(ref T obj) it is the first function parameter.
	string paramName = templateParamName;
	if (paramName.empty && !symbol.functionParameters.empty)
	{
		auto first = symbol.functionParameters[0];
		if (first.type !is null && !first.type.name.empty)
			paramName = first.type.name.idup;
	}
	if (paramName.empty)
		paramName = "T";

	// Split `A && B` into conjuncts; every one must hold. A conjunct we
	// can't evaluate makes the whole constraint unknown (no opinion)
	// rather than satisfied — e.g. `isInputRange!R` must never look like
	// a match.
	bool sawUnknown = false;
	foreach (conjunct; splitAnd(constraint))
	{
		final switch (matchSingle(conjunct, paramName, type))
		{
		case ConstraintMatch.noMatch:
			return ConstraintMatch.noMatch;
		case ConstraintMatch.unknown:
			sawUnknown = true;
			break;
		case ConstraintMatch.match:
			break;
		}
	}
	return sawUnknown ? ConstraintMatch.unknown : ConstraintMatch.match;
}

/// Splits a constraint on top-level `&&`, ignoring `&&` inside parens.
private string[] splitAnd(string constraint)
{
	string[] parts;
	size_t depth;
	size_t start;
	foreach (size_t i, immutable char c; constraint)
	{
		if (c == '(')
			depth++;
		else if (c == ')')
			depth--;
		else if (c == '&' && depth == 0 && i + 1 < constraint.length
			&& constraint[i + 1] == '&')
		{
			parts ~= constraint[start .. i].stripLeft.stripRight;
			start = i + 2;
		}
	}
	parts ~= constraint[start .. $].stripLeft.stripRight;
	return parts;
}

/// Matches one `&&`-free conjunct.
private ConstraintMatch matchSingle(string conjunct, string paramName,
	const(DSymbol)* type)
{
	bool negated;
	if (conjunct.startsWith("!"))
	{
		negated = true;
		conjunct = conjunct[1 .. $].stripLeft;
	}

	ConstraintMatch result;
	if (conjunct.startsWith("__traits(isStaticArray"))
		result = kindMatchesStaticArray(type);
	else if (conjunct.startsWith("is("))
		result = matchIsExpression(conjunct, paramName, type);
	else
		// Unrecognized form (isInputRange!R, arbitrary expressions, ...)
		return ConstraintMatch.unknown;

	if (result == ConstraintMatch.unknown)
		return ConstraintMatch.unknown;
	return negated ? (result == ConstraintMatch.match
		? ConstraintMatch.noMatch : ConstraintMatch.match) : result;
}

/// `is(T == struct)` and friends: compare the specialization against the kind.
private ConstraintMatch matchIsExpression(string expr, string paramName,
	const(DSymbol)* type)
{
	// Extract the identifier between `is(` and the following `==`/`:`/`)`.
	// The formatter renders `is(T == struct)` with single spaces.
	size_t i = 3; // skip "is("
	while (i < expr.length && (expr[i] == ' ' || expr[i] == '\t'))
		i++;
	size_t nameStart = i;
	while (i < expr.length && (expr[i].isAlpha || expr[i] == '_'))
		i++;
	if (i == nameStart)
		return ConstraintMatch.unknown;
	string name = expr[nameStart .. i];
	if (name != paramName)
		return ConstraintMatch.unknown; // constrains a different parameter

	// Find the comparison operator
	while (i < expr.length && (expr[i] == ' ' || expr[i] == '\t'))
		i++;
	if (i + 1 >= expr.length || expr[i] != '=' || expr[i + 1] != '=')
		return ConstraintMatch.unknown; // `is(T)` / `is(T : X)` — no opinion
	i += 2;
	while (i < expr.length && (expr[i] == ' ' || expr[i] == '\t'))
		i++;

	// Extract the specialization word
	size_t specStart = i;
	while (i < expr.length && (expr[i].isAlpha || expr[i] == '_'))
		i++;
	if (i == specStart)
		return ConstraintMatch.unknown;
	string spec = expr[specStart .. i];

	// A trailing `)` must follow (possibly after whitespace)
	size_t j = i;
	while (j < expr.length && (expr[j] == ' ' || expr[j] == '\t'))
		j++;
	if (j >= expr.length || expr[j] != ')')
		return ConstraintMatch.unknown; // e.g. `is(T == SomeType!(...))`

	CompletionKind expected;
	switch (spec)
	{
	case "struct": expected = CompletionKind.structName; break;
	case "class": expected = CompletionKind.className; break;
	case "interface": expected = CompletionKind.interfaceName; break;
	case "union": expected = CompletionKind.unionName; break;
	case "enum": expected = CompletionKind.enumName; break;
	default: return ConstraintMatch.unknown; // function, delegate, ...
	}
	return type.kind == expected ? ConstraintMatch.match : ConstraintMatch.noMatch;
}

private ConstraintMatch kindMatchesStaticArray(const(DSymbol)* type)
{
	// DCD models static arrays with the array qualifier; dynamic arrays use
	// it too, so this can only be a positive signal, never a rejection.
	if (type.qualifier == SymbolQualifier.array)
		return ConstraintMatch.match;
	return ConstraintMatch.unknown;
}

private bool isAlpha(immutable char c) pure nothrow @safe @nogc
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

unittest
{
	// is(T == struct) matches a struct, rejects a class, no opinion on a
	// constraint we don't understand.
	DSymbol structType = DSymbol("Mama", CompletionKind.structName);
	DSymbol classType = DSymbol("C", CompletionKind.className);

	DSymbol fn = DSymbol("destroy", CompletionKind.functionName);
	fn.constraintText = internString("is(T == struct)");
	assert(matchConstraint(&fn, &structType) == ConstraintMatch.match);
	assert(matchConstraint(&fn, &classType) == ConstraintMatch.noMatch);

	// negation
	fn.constraintText = internString("!is(T == struct)");
	assert(matchConstraint(&fn, &structType) == ConstraintMatch.noMatch);
	assert(matchConstraint(&fn, &classType) == ConstraintMatch.match);

	// the catch-all destroy overload: negated conjunction
	fn.constraintText = internString("!is(T == struct) && !is(T == interface) && !is(T == class) && !__traits(isStaticArray, T)");
	assert(matchConstraint(&fn, &structType) == ConstraintMatch.noMatch);
	assert(matchConstraint(&fn, &classType) == ConstraintMatch.noMatch);

	// unknown forms stay unknown
	fn.constraintText = internString("isInputRange!R");
	assert(matchConstraint(&fn, &structType) == ConstraintMatch.unknown);
	fn.constraintText = typeof(fn.constraintText).init;
	assert(matchConstraint(&fn, &structType) == ConstraintMatch.unknown);

	// constrains a different parameter name
	fn.constraintText = internString("is(U == struct)");
	assert(matchConstraint(&fn, &structType) == ConstraintMatch.unknown);
}

T getExpression(T)(T beforeTokens)
{
	enum EXPRESSION_LOOP_BREAK = q{
		if (i + 1 < beforeTokens.length) switch (beforeTokens[i + 1].type)
		{
		mixin (TYPE_IDENT_AND_LITERAL_CASES);
			i++;
			break expressionLoop;
		default:
			break;
		}
	};

	if (beforeTokens.length == 0)
		return beforeTokens[0 .. 0];
	size_t i = beforeTokens.length - 1;
	size_t sliceEnd = beforeTokens.length;
	IdType open;
	IdType close;
	uint skipCount = 0;

	expressionLoop: while (true)
	{
		switch (beforeTokens[i].type)
		{
		case tok!"import":
			i++;
			break expressionLoop;
		mixin (TYPE_IDENT_AND_LITERAL_CASES);
			mixin (EXPRESSION_LOOP_BREAK);
			break;
		case tok!".":
			break;
		case tok!")":
			open = tok!")";
			close = tok!"(";
			goto skip;
		case tok!"]":
			open = tok!"]";
			close = tok!"[";
		skip:
			mixin (EXPRESSION_LOOP_BREAK);
			immutable bookmark = i;
			i = beforeTokens.skipParenReverse(i, open, close);

			skipCount++;

			// check the current token after skipping parens to the left.
			// if it's a loop keyword, pretend we never skipped the parens.
			if (i > 0) switch (beforeTokens[i - 1].type)
			{
				case tok!"scope":
				case tok!"if":
				case tok!"while":
				case tok!"for":
				case tok!"foreach":
				case tok!"foreach_reverse":
				case tok!"do":
				case tok!"cast":
				case tok!"catch":
					i = bookmark + 1;
					break expressionLoop;
				case tok!"!":
					// only break if the bang is for a template instance
					if (i - 2 >= 0  && beforeTokens[i - 2].type == tok!"identifier" && skipCount == 1)
					{
						sliceEnd = i - 1;
						i -= 2;
						break expressionLoop;
					}
					break;
				default:
					break;
			}
			break;
		default:
			i++;
			break expressionLoop;
		}
		if (i == 0)
			break;
		else
			i--;
	}
	return beforeTokens[i .. sliceEnd];
}

