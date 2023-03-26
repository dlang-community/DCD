module dsymbol.utils;
import dparse.lexer : tok, IdType, Token;

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

