module dsymbol.ufcs;

import dsymbol.symbol;
import dsymbol.scope_;
import dsymbol.builtin.names;
import dsymbol.utils;
import dparse.lexer : tok, Token;
import std.functional : unaryFun;
import std.algorithm;
import std.array;
import std.range;
import std.string;
import std.regex;
import containers.hashset : HashSet;
import std.experimental.logger;

enum UFCSCompletionContext
{
    DotCompletion,
    ParenCompletion,
    UnknownCompletion
}

struct TokenCursorResult
{
    UFCSCompletionContext completionContext = UFCSCompletionContext.UnknownCompletion;
    istring functionName;
    istring symbolIdentifierName;
}

// https://dlang.org/spec/type.html#implicit-conversions
enum string[string] INTEGER_PROMOTIONS = [
        "bool": "int",
        "byte": "int",
        "ubyte": "int",
        "short": "int",
        "ushort": "int",
        "char": "int",
        "wchar": "int",
        "dchar": "uint",
    ];

enum MAX_RECURSION_DEPTH = 50;

private DSymbol* deduceSymbolType(DSymbol* symbol)
{
    DSymbol* symbolType = symbol.type;
    while (symbolType !is null && (symbolType.qualifier == SymbolQualifier.func
            || symbolType.kind == CompletionKind.functionName
            || symbolType.kind == CompletionKind.importSymbol
            || symbolType.kind == CompletionKind.aliasName))
    {
        if (symbolType.type is null || symbolType.type is symbolType)
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

private TokenCursorResult getCursorToken(const(Token)[] tokens, size_t cursorPosition)
{
    auto sortedTokens = assumeSorted(tokens);
    auto sortedBeforeTokens = sortedTokens.lowerBound(cursorPosition);

    TokenCursorResult tokenCursorResult;

    if (sortedBeforeTokens.empty) {
        return tokenCursorResult;
    }

    if (sortedBeforeTokens.length >= 2 
        && sortedBeforeTokens[$ - 1].type is tok!"."
        && sortedBeforeTokens[$ - 2].type is tok!"identifier")
    {
        // Check if it's UFCS dot completion
        tokenCursorResult.completionContext = UFCSCompletionContext.DotCompletion;
        tokenCursorResult.symbolIdentifierName = istring(sortedBeforeTokens[$ - 2].text);
        return tokenCursorResult;
    }
    else
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
            tokenCursorResult.completionContext = UFCSCompletionContext.ParenCompletion;
            tokenCursorResult.symbolIdentifierName = istring(slicedAtParen[$ - 4].text);
            tokenCursorResult.functionName = istring(slicedAtParen[$ - 2].text);
            return tokenCursorResult;
        }

    }
    // if none then it's unknown
    return tokenCursorResult;
}

private void getUFCSSymbols(T, Y)(ref T localAppender, ref Y globalAppender, Scope* completionScope, size_t cursorPosition)

{

    Scope* currentScope = completionScope.getScopeByCursor(cursorPosition);
    if (currentScope is null)
    {
        return;
    }

    DSymbol*[] cursorSymbols = currentScope.getSymbolsInCursorScope(cursorPosition);
    if (cursorSymbols.empty)
    {
        return;
    }

    auto filteredSymbols = cursorSymbols.filter!(s => s.kind == CompletionKind.functionName).array;

    foreach (DSymbol* sym; filteredSymbols)
    {
        globalAppender.put(sym);
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

DSymbol*[] getUFCSSymbolsForCursor(Scope* completionScope, ref const(Token)[] tokens, size_t cursorPosition)
{
    DSymbol* cursorSymbol;
    DSymbol* cursorSymbolType;

    TokenCursorResult tokenCursorResult = getCursorToken(tokens, cursorPosition);

    if (tokenCursorResult.completionContext is UFCSCompletionContext.UnknownCompletion)
    {
        trace("Is not a valid UFCS completion");
        return [];
    }

    cursorSymbol = completionScope.getFirstSymbolByNameAndCursor(
        tokenCursorResult.symbolIdentifierName, cursorPosition);

    if (cursorSymbol is null)
    {
        warning("Coudn't find symbol ", tokenCursorResult.symbolIdentifierName);
        return [];
    }

    if (cursorSymbol.isInvalidForUFCSCompletion)
    {
        trace("CursorSymbol is invalid");
        return [];
    }

    cursorSymbolType = deduceSymbolType(cursorSymbol);

    if (cursorSymbolType is null)
    {
        return [];
    }

    if (cursorSymbolType.isInvalidForUFCSCompletion)
    {
        trace("CursorSymbolType isn't valid for UFCS completion");
        return [];
    }

    if (tokenCursorResult.completionContext == UFCSCompletionContext.ParenCompletion)
    {
        return getUFCSSymbolsForParenCompletion(cursorSymbolType, completionScope, tokenCursorResult.functionName, cursorPosition);
    }
    else
    {
        return getUFCSSymbolsForDotCompletion(cursorSymbolType, completionScope, cursorPosition);
    }

}

private DSymbol*[] getUFCSSymbolsForDotCompletion(DSymbol* symbolType, Scope* completionScope, size_t cursorPosition)
{
    // local appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType), DSymbol*[]) localAppender;
    // global appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType, true), DSymbol*[]) globalAppender;

    getUFCSSymbols(localAppender, globalAppender, completionScope, cursorPosition);

    return localAppender.data ~ globalAppender.data;
}

DSymbol*[] getUFCSSymbolsForParenCompletion(DSymbol* symbolType, Scope* completionScope, istring searchWord, size_t cursorPosition)
{
    // local appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType) && a.name.among(searchWord), DSymbol*[]) localAppender;
    // global appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType, true) && a.name.among(searchWord), DSymbol*[]) globalAppender;

    getUFCSSymbols(localAppender, globalAppender, completionScope, cursorPosition);

    return localAppender.data ~ globalAppender.data;

}

private bool willImplicitBeUpcasted(string from, string to)
{
    string* found = from in INTEGER_PROMOTIONS;
    if (!found)
    {
        return false;
    }

    return INTEGER_PROMOTIONS[from] == to;
}

private bool matchAliasThis(const(DSymbol)* beforeDotType, DSymbol* incomingSymbol, int recursionDepth)
{
    // For now we are only resolving the first alias this symbol
    // when multiple alias this are supported, we can rethink another solution
    if (beforeDotType.aliasThisSymbols.empty || beforeDotType.aliasThisSymbols.front == beforeDotType)
    {
        return false;
    }

    //Incrementing depth count to ensure we don't run into an infinite loop
    recursionDepth++;

    return isCallableWithArg(incomingSymbol, beforeDotType.aliasThisSymbols.front.type, false, recursionDepth);
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
bool isCallableWithArg(DSymbol* incomingSymbol, const(DSymbol)* beforeDotType, bool isGlobalScope = false, int recursionDepth = 0)
{
    if (!incomingSymbol || !beforeDotType
        || (isGlobalScope && incomingSymbol.protection == tok!"private") || recursionDepth > MAX_RECURSION_DEPTH)
    {
        return false;
    }

    if (incomingSymbol.kind == CompletionKind.functionName && !incomingSymbol
        .functionParameters.empty)
    {
        if (beforeDotType is incomingSymbol.functionParameters.front.type
            || incomingSymbol.functionParameters.front.type.kind is CompletionKind.typeTmpParam // non constrained template
            || willImplicitBeUpcasted(beforeDotType.name, incomingSymbol
                .functionParameters.front.type.name)
            || matchAliasThis(beforeDotType, incomingSymbol, recursionDepth))
        {
            incomingSymbol.kind = CompletionKind.ufcsName;
            return true;
        }

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
    assert(!willImplicitBeUpcasted("A", "B"));
    assert(willImplicitBeUpcasted("bool", "int"));
}
