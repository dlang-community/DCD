module dsymbol.ufcs;

import dsymbol.symbol;
import dsymbol.scope_;
import dsymbol.builtin.names;
import dsymbol.utils;
import dparse.lexer : tok, Token, isStringLiteral, isNumberLiteral;
import dparse.strings;
import std.functional : unaryFun;
import std.algorithm;
import std.algorithm.searching : countUntil;
import std.array;
import std.range;
import std.string;
import std.regex;
import containers.hashset : HashSet;
import std.experimental.logger;
alias SortedTokens = SortedRange!(const(Token)[], "a < b");

struct ExpressionInfo
{
    const(DSymbol)* type;
    bool assumingLvalue; // We only assume else we need to do life time analysis.
    bool isFromFunction;
    string name;
}

enum CompletionContext
{
    UnknownCompletion,
    DotCompletion,
    ParenCompletion,
}

struct TokenCursorResult
{
    CompletionContext completionContext;
    istring functionName;
    const(Token)[] expressionTokens;
    string partialIdentifier;
}

// https://dlang.org/spec/type.html#implicit-conversions
enum string[string] INTEGER_PROMOTIONS = [
    "bool": "byte",
    "byte": "int",
    "ubyte": "int",
    "short": "int",
    "ushort": "int",
    "char": "int",
    "wchar": "int",
    "dchar": "uint",

    // found in test case extra/tc_ufcs_all_kinds:
    "int": "float",
    "uint": "float",
    "long": "float",
    "ulong": "float",

    "float": "double",
    "double": "real",
];

enum MAX_NUMBER_OF_MATCHING_RUNS = 50;

private const(Token)* findUFCSBaseToken( const(Token)[] tokens)
{
    if (tokens.empty)
        return null;

    int depth = 0;

    // Walk backwards to skip nested parentheses/brackets/braces
    for (long i = tokens.length - 1; i >= 0; i--)
    {
        auto t = tokens[i].type;

        // Handle closing of nested scopes
        if (t is tok!")" || t is tok!"]" || t is tok!"}")
        {
            depth++;
            continue;
        }

        // Handle opening of nested scopes
        if (t is tok!"(" || t is tok!"[" || t is tok!"{")
        {
            depth--;
            continue;
        }

        if (depth != 0)
            continue;

        // If we hit a literal or identifier, that's likely our base
        if (t is tok!"identifier" || isStringLiteral(t) || t is tok!"intLiteral" || t is tok!"floatLiteral")
        {
            return &tokens[i];
        }

        // Stop at anything else that breaks the expression (operators, keywords, etc.)
        return &tokens[i + 1];
    }

    // If we never returned inside the loop, the first token is the base
    return &tokens[0];
}

private const(Token)* findExpressionBase(const(Token)[] tokens)
{
    foreach (i, t; tokens)
    {
        // literals are always a base
        if (isStringLiteral(t.type) || isNumberLiteral(t.type) || t.type is tok!"identifier")
            return &tokens[i];
    }
    return tokens.ptr; // fallback
}

private const(DSymbol)* deduceExpressionType(
    Scope* completionScope,
    const(Token)[] exprTokens,
    size_t cursorPosition)
{

    if (exprTokens.empty)
    {
        return null;
    }

    auto firstToken = findUFCSBaseToken(exprTokens);
    if (isStringLiteral(firstToken.type))
    {
        return completionScope.getFirstSymbolByNameAndCursor(
            symbolNameToTypeName(STRING_LITERAL_SYMBOL_NAME), cursorPosition);
    }

    auto currentType = deduceSymbolTypeByToken(completionScope, *firstToken, cursorPosition);


    if (currentType is null)
        return null;

    // 2. Walk through the expression left → right
    for (size_t i = 1; i < exprTokens.length; i++)
    {
        auto t = exprTokens[i].type;

        // ---- Handle function call: foo() ----
        if (t is tok!"(")
        {
            // Skip to matching ')'
            int depth = 1;
            size_t j = i + 1;

            while (j < exprTokens.length && depth > 0)
            {
                if (exprTokens[j].type is tok!"(")
                    depth++;
                else if (exprTokens[j].type is tok!")")
                    depth--;

                j++;
            }

            // Function call → move to return type
            if (currentType !is null && currentType.type !is null)
            {
                currentType = currentType.type;
            }

            i = j - 1;
            continue;
        }

        // ---- Handle dot call
        if (t is tok!"." &&
            i + 1 < exprTokens.length &&
            exprTokens[i + 1].type is tok!"identifier")
        {
            auto name = istring(exprTokens[i + 1].text);

            // Get UFCS candidates for current type
            ExpressionInfo beforeDotType;
            beforeDotType.type = currentType;
            beforeDotType.assumingLvalue = false;
            // check if there it's from a function
            auto functionSymbol = completionScope.getFirstSymbolByNameAndCursor(istring(firstToken.text), cursorPosition);
            if (functionSymbol) {
                beforeDotType.isFromFunction = functionSymbol.qualifier == SymbolQualifier.func;
                beforeDotType.name = functionSymbol.name;
            }

            auto candidates = getUFCSSymbolsForDotCompletion(
                beforeDotType,
                completionScope,
                cursorPosition,
                ""
            );

            const(DSymbol)* match = null;

            foreach (c; candidates)
            {
                if (c.name == name)
                {
                    match = c;
                    break;
                }
            }

            // Invalid UFCS chain
            if (match is null) {
                return null;
            }

            // Update current type (this is the chain step)
            currentType = match.type;

            i++; // skip identifier
            continue;
        }
    }
    return currentType;
}

private const(DSymbol)* deduceSymbolTypeByToken(Scope* completionScope, scope ref const(Token) significantToken, size_t cursorPosition)
{

    const(DSymbol)* symbol = completionScope.getFirstSymbolByNameAndCursor(
        istring(significantToken.text), cursorPosition);

    if (symbol is null)
    {
        return null;
    }

    const(DSymbol)* symbolType = symbol.type;
    while (symbolType !is null && (symbolType.qualifier == SymbolQualifier.func
            || symbolType.kind == CompletionKind.functionName
            || symbolType.kind == CompletionKind.importSymbol
            || symbolType.kind == CompletionKind.aliasName))
    {
        if (symbolType.type is null
            || symbolType.type is symbolType
            || symbolType.name.data == "string") // special case for string
        {
            break;
        }
        //look at next type to deduce
        symbolType = symbolType.type;
    }

    return symbolType;

}

// Check if beforeDotSymbol is null or void
private bool isInvalidForUFCSCompletion(const(DSymbol)* beforeDotSymbol)
{
    return beforeDotSymbol is null
        || beforeDotSymbol.name is getBuiltinTypeName(tok!"void")
        || (beforeDotSymbol.type !is null && beforeDotSymbol.type.name is getBuiltinTypeName(
                tok!"void"));
}

const(Token)* findUFCSExpressionStart(SortedTokens tokens)
{
    int depth = 0;

    for (long i = tokens.length - 1; i >= 0; i--)
    {
        auto t = tokens[i].type;

        // Handle nesting
        if (t is tok!")" || t is tok!"]" || t is tok!"}")
        {
            depth++;
            continue;
        }

        if (t is tok!"(" || t is tok!"[" || t is tok!"{")
        {
            depth--;
            continue;
        }

        if (depth != 0)
            continue;

        // Allow chaining: f.papa().x
        if (t is tok!"." ||
            t is tok!"identifier" ||
            t is tok!"stringLiteral")
        {
            continue;
        }

        // Stop when hitting something that breaks expression
        return &tokens[i + 1];
    }

    // Entire range is the expression
    return &tokens[0];
}

private TokenCursorResult getCursorToken(Scope* completionScope, const(Token)[] tokens, size_t cursorPosition)
{
    SortedTokens sortedTokens = assumeSorted(tokens);
    SortedTokens sortedBeforeTokens = sortedTokens.lowerBound(cursorPosition);

    TokenCursorResult tokenCursorResult;

    if (sortedBeforeTokens.empty)
    {
        return tokenCursorResult;
    }

    // Handle partially completed
    if (sortedBeforeTokens[$ - 1].type is tok!"identifier")
    {
        tokenCursorResult.partialIdentifier = sortedBeforeTokens[$ - 1].text;
        sortedBeforeTokens = sortedBeforeTokens[0 .. $ - 1];
    }

    // Handle dot completion
    if (!sortedBeforeTokens.empty &&
        sortedBeforeTokens[$ - 1].type is tok!".")
    {
        const(Token)* exprStart = findUFCSExpressionStart(sortedBeforeTokens);

        if (exprStart is null)
            return tokenCursorResult;

        size_t start = exprStart - tokens.ptr;
        size_t end = (&sortedBeforeTokens[$ - 1]) - tokens.ptr;

        auto exprTokens = tokens[start .. end];

        tokenCursorResult.expressionTokens = exprTokens;
        tokenCursorResult.completionContext = CompletionContext.DotCompletion;
        return tokenCursorResult;
    }
    else if (!tokenCursorResult.partialIdentifier.length)
    {
        // Check if it's UFCS paren completion
        size_t index = goBackToOpenParen(sortedBeforeTokens);

        if (index == size_t.max)
        {
            return tokenCursorResult;
        }

        auto slicedAtParen = sortedBeforeTokens[0 .. index];
        if (slicedAtParen.length >= 4
            && slicedAtParen[$ - 4].type is tok!"identifier"
            && slicedAtParen[$ - 3].type is tok!"."
            && slicedAtParen[$ - 2].type is tok!"identifier"
            && slicedAtParen[$ - 1].type is tok!"(")
        {
            tokenCursorResult.expressionTokens = slicedAtParen[0 .. $ - 3].array;
            tokenCursorResult.completionContext = CompletionContext.ParenCompletion;
            tokenCursorResult.functionName = istring(slicedAtParen[$ - 2].text);
            return tokenCursorResult;
        }

    }
    // if none then it's unknown
    return tokenCursorResult;
}

private void getUFCSSymbols(T, Y)(scope ref T localAppender, scope ref Y globalAppender, Scope* completionScope, size_t cursorPosition)
{

    Scope* currentScope = completionScope.getScopeByCursor(cursorPosition);
    if (currentScope is null)
    {
        return;
    }

    HashSet!size_t visited;

    while (currentScope !is null && currentScope.parent !is null)
    {
        auto localImports = currentScope.symbols.filter!(a => a.kind == CompletionKind.importSymbol);
        foreach (sym; localImports)
        {
            if (sym.type is null)
                continue;
            if (sym.qualifier == SymbolQualifier.selectiveImport)
                localAppender.put(sym.type);
            else
                sym.type.getParts(istring(null), localAppender, visited);
        }

        currentScope = currentScope.parent;
    }

    if (currentScope is null)
    {
        return;
    }
    assert(currentScope !is null);
    assert(currentScope.parent is null);

    foreach (sym; currentScope.symbols)
    {
        if (sym.kind != CompletionKind.importSymbol)
            localAppender.put(sym);
        else if (sym.type !is null)
        {
            if (sym.qualifier == SymbolQualifier.selectiveImport)
                localAppender.put(sym.type);
            else
            {
                sym.type.getParts(istring(null), globalAppender, visited);
            }
        }
    }
}

DSymbol*[] getUFCSSymbolsForCursor(Scope* completionScope, scope ref const(Token)[] tokens, size_t cursorPosition)
{
    TokenCursorResult tokenCursorResult = getCursorToken(completionScope, tokens, cursorPosition);

    if (tokenCursorResult.completionContext is CompletionContext.UnknownCompletion)
    {
        trace("Is not a valid UFCS completion");
        return [];
    }

    ExpressionInfo deducedSymbolType;
    deducedSymbolType.type = deduceExpressionType(completionScope, tokenCursorResult.expressionTokens, cursorPosition);

    if (deducedSymbolType.type is null)
    {
        return [];
    }

    if (deducedSymbolType.type.isInvalidForUFCSCompletion)
    {
        trace("CursorSymbolType isn't valid for UFCS completion");
        return [];
    }

    if (tokenCursorResult.completionContext == CompletionContext.ParenCompletion)
    {
        return getUFCSSymbolsForParenCompletion(deducedSymbolType, completionScope, tokenCursorResult.functionName, cursorPosition);
    }
    else
    {
        return getUFCSSymbolsForDotCompletion(deducedSymbolType, completionScope, cursorPosition, tokenCursorResult
                .partialIdentifier);
    }

}

private DSymbol*[] getUFCSSymbolsForDotCompletion(ExpressionInfo symbolType, Scope* completionScope, size_t cursorPosition, string partial)
{
    // local appender
    FilteredAppender!((DSymbol* a) =>
            a.isCallableWithArg(symbolType)
            && toUpper(a.name.data).startsWith(toUpper(partial)),
        DSymbol*[]) localAppender;
    // global appender
    FilteredAppender!((DSymbol* a) =>
            a.isCallableWithArg(symbolType, true)
            && toUpper(a.name.data).startsWith(toUpper(partial)),
        DSymbol*[]) globalAppender;

    getUFCSSymbols(localAppender, globalAppender, completionScope, cursorPosition);

    return localAppender.data ~ globalAppender.data;
}

private DSymbol*[] getUFCSSymbolsForParenCompletion(ExpressionInfo symbolType, Scope* completionScope, istring searchWord, size_t cursorPosition)
{
    // local appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType) && a.name.among(searchWord), DSymbol*[]) localAppender;
    // global appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType, true) && a.name.among(searchWord), DSymbol*[]) globalAppender;

    getUFCSSymbols(localAppender, globalAppender, completionScope, cursorPosition);

    return localAppender.data ~ globalAppender.data;

}

private bool willImplicitBeUpcasted(scope ref const(DSymbol) incomingSymbolType, scope ref const(
        DSymbol) significantSymbolType)
{
    string fromTypeName = significantSymbolType.name.data;
    string toTypeName = incomingSymbolType.name.data;

    return typeWillBeUpcastedTo(fromTypeName, toTypeName);
}

private bool typeWillBeUpcastedTo(string from, string to)
{
    while (true)
    {
        if (typeWillIntegerUpcastedTo(from, to))
            return true;
        if (from.typeIsFloating && to.typeIsFloating)
            return true;

        if (auto promotionType = from in INTEGER_PROMOTIONS)
        {
            if (*promotionType == to)
                return true;
            from = *promotionType;
        }
        else
            return false;
    }
}

private bool typeWillIntegerUpcastedTo(string from, string to)
{
    int fromIntSize = getIntegerTypeSize(from);
    int toIntSize = getIntegerTypeSize(to);
    return fromIntSize != 0 && toIntSize != 0 && fromIntSize <= toIntSize;
}

private int getIntegerTypeSize(string type)
{
    switch (type)
    {
        // ordered by subjective frequency of use, since the compiler may use that
        // for optimization.
    case "int", "uint":
        return 4;
    case "long", "ulong":
        return 8;
    case "byte", "ubyte":
        return 1;
    case "short", "ushort":
        return 2;
    case "dchar":
        return 4;
    case "wchar":
        return 2;
    case "char":
        return 1;
    default:
        return 0;
    }
}

private bool typeIsFloating(string type)
{
    switch (type)
    {
    case "float":
    case "double":
    case "real":
        return true;
    default:
        return false;
    }
}

bool isNonConstrainedTemplate(scope ref const(DSymbol) symbolType)
{
    return symbolType.kind is CompletionKind.typeTmpParam;
}

private bool matchesWithTypeOfPointer(scope ref const(DSymbol) incomingSymbolType, scope ref const(
        DSymbol) significantSymbolType)
{
    return incomingSymbolType.qualifier == SymbolQualifier.pointer
        && significantSymbolType.qualifier == SymbolQualifier.pointer
        && incomingSymbolType.type is significantSymbolType.type;
}

private bool matchesWithTypeOfArray(scope ref const(DSymbol) incomingSymbolType, scope ref const(
        DSymbol) cursorSymbolType)
{
    return incomingSymbolType.qualifier == SymbolQualifier.array
        && cursorSymbolType.qualifier == SymbolQualifier.array
        && incomingSymbolType.type is cursorSymbolType.type;

}

private bool matchStringLikeTypes(scope ref const(DSymbol) incomingSymbolType, scope ref const(DSymbol) significantSymbolType)
{
    if ((incomingSymbolType.name.data == "string" || incomingSymbolType.name.data == "wstring"
            || incomingSymbolType.name.data == "dstring") && (significantSymbolType.name.data == "string" || significantSymbolType.name.data == "wstring"
            || significantSymbolType.name.data == "dstring"))
    {
        return true;
    }
    return false;
}

private bool typeMatchesWith(scope ref const(DSymbol) incomingSymbolType, scope ref const(DSymbol) significantSymbolType)
{
    return incomingSymbolType is significantSymbolType
        || isNonConstrainedTemplate(
            incomingSymbolType)
        || matchesWithTypeOfArray(incomingSymbolType, significantSymbolType)
        || matchesWithTypeOfPointer(incomingSymbolType, significantSymbolType)
        || matchStringLikeTypes(incomingSymbolType, significantSymbolType);

}

private bool matchSymbolType(const(DSymbol)* firstParameter, const(DSymbol)* significantSymbolType)
{

    auto currentSignificantSymbolType = significantSymbolType;
    uint numberOfRetries = 0;

    do
    {
        if (typeMatchesWith(*firstParameter.type, *currentSignificantSymbolType))
        {
            return true;
        }

        if (!(firstParameter.parameterIsRef || firstParameter.parameterIsOut)
            && willImplicitBeUpcasted(*firstParameter.type, *currentSignificantSymbolType))
            return true;

        if (currentSignificantSymbolType.aliasThisSymbols.empty || currentSignificantSymbolType is currentSignificantSymbolType
            .aliasThisSymbols.front)
        {
            return false;
        }

        numberOfRetries++;
        // For now we are only resolving the first alias this symbol
        // when multiple alias this are supported, we can rethink another solution
        currentSignificantSymbolType = currentSignificantSymbolType.aliasThisSymbols.front.type;
    }
    while (numberOfRetries <= MAX_NUMBER_OF_MATCHING_RUNS);
    return false;
}

/**
 * Params:
 *     incomingSymbol = the function symbol to check if it is valid for UFCS with `beforeDotType`.
 *     beforeDotType = the type of the expression that's used before the dot.
 *     isGlobalScope = the symbol to check
 * Returns:
 *     `true` if `incomingSymbols`' first parameter matches `beforeDotType`
 *     `false` otherwise
 */
bool isCallableWithArg(const(DSymbol)* incomingSymbol, ExpressionInfo beforeDotType, bool isGlobalScope = false)
{
    if (incomingSymbol is null
        || beforeDotType.type is null
        || isGlobalScope && incomingSymbol.protection is tok!"private") // don't show private functions if we are in global scope
        {
        return false;
    }

    if (incomingSymbol.kind is CompletionKind.functionName && !incomingSymbol.functionParameters.empty && incomingSymbol
        .functionParameters.front.type)
    {
        auto firstParam = incomingSymbol.functionParameters.front;
        return matchSymbolType(firstParam, beforeDotType.type);
    }
    return false;
}

/// $(D appender) with filter on $(D put)
struct FilteredAppender(alias predicate, T:
    T[] = DSymbol*[]) if (__traits(compiles, unaryFun!predicate(T.init) ? 0 : 0))
{
    alias pred = unaryFun!predicate;
    private Appender!(T[]) app;

    void put(T item)
    {
        if (pred(item))
            app.put(item);
    }

    void put(R)(R items) if (isInputRange!R && __traits(compiles, put(R.init.front)))
    {
        foreach (item; items)
            put(item);
    }

    void opOpAssign(string op : "~")(T rhs)
    {
        put(rhs);
    }

    alias app this;
}

@safe pure nothrow unittest
{
    FilteredAppender!("a%2", int[]) app;
    app.put(iota(10));
    assert(app.data == [1, 3, 5, 7, 9]);
}

unittest
{
    assert(!typeWillBeUpcastedTo("A", "B"));
    assert(typeWillBeUpcastedTo("bool", "int"));
}
