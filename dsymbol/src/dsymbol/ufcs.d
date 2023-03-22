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
    istring symbolIdentifierName;
    string partialIdentifier;
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

enum MAX_NUMBER_OF_MATCHING_RUNS = 50;

private const(DSymbol)* deduceSymbolType(const(DSymbol)* symbol)
{
    const(DSymbol)* symbolType = symbol.type;
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

    // move before identifier for
    if (sortedBeforeTokens[$ - 1].type is tok!"identifier")
    {
        tokenCursorResult.partialIdentifier = sortedBeforeTokens[$ - 1].text;
        sortedBeforeTokens = sortedBeforeTokens[0 .. $ - 1];
    }

    if (sortedBeforeTokens.length >= 2 
        && sortedBeforeTokens[$ - 1].type is tok!"."
        && sortedBeforeTokens[$ - 2].type is tok!"identifier")
    {
        // Check if it's UFCS dot completion
        tokenCursorResult.completionContext = CompletionContext.DotCompletion;
        tokenCursorResult.symbolIdentifierName = istring(sortedBeforeTokens[$ - 2].text);
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
            tokenCursorResult.completionContext = CompletionContext.ParenCompletion;
            tokenCursorResult.symbolIdentifierName = istring(slicedAtParen[$ - 4].text);
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
    TokenCursorResult tokenCursorResult = getCursorToken(tokens, cursorPosition);

    if (tokenCursorResult.completionContext is CompletionContext.UnknownCompletion)
    {
        trace("Is not a valid UFCS completion");
        return [];
    }

    const(DSymbol)* cursorSymbol = completionScope.getFirstSymbolByNameAndCursor(
        tokenCursorResult.symbolIdentifierName, cursorPosition);

    if (cursorSymbol is null)
    {
        warning("Coudn't find symbol ", tokenCursorResult.symbolIdentifierName);
        return [];
    }

    if (cursorSymbol.isInvalidForUFCSCompletion)
    {
        trace("CursorSymbol is invalid for UFCS");
        return [];
    }

    const(DSymbol)* cursorSymbolType = deduceSymbolType(cursorSymbol);

    if (cursorSymbolType is null)
    {
        return [];
    }

    if (cursorSymbolType.isInvalidForUFCSCompletion)
    {
        trace("CursorSymbolType isn't valid for UFCS completion");
        return [];
    }

    if (tokenCursorResult.completionContext == CompletionContext.ParenCompletion)
    {
        return getUFCSSymbolsForParenCompletion(cursorSymbolType, completionScope, tokenCursorResult.functionName, cursorPosition);
    }
    else
    {
        return getUFCSSymbolsForDotCompletion(cursorSymbolType, completionScope, cursorPosition, tokenCursorResult.partialIdentifier);
    }

}

private DSymbol*[] getUFCSSymbolsForDotCompletion(const(DSymbol)* symbolType, Scope* completionScope, size_t cursorPosition, string partial)
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

private DSymbol*[] getUFCSSymbolsForParenCompletion(const(DSymbol)* symbolType, Scope* completionScope, istring searchWord, size_t cursorPosition)
{
    // local appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType) && a.name.among(searchWord), DSymbol*[]) localAppender;
    // global appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType, true) && a.name.among(searchWord), DSymbol*[]) globalAppender;

    getUFCSSymbols(localAppender, globalAppender, completionScope, cursorPosition);

    return localAppender.data ~ globalAppender.data;

}

private bool willImplicitBeUpcasted(scope ref const(DSymbol) incomingSymbolType, scope ref const(DSymbol) significantSymbolType)
{
    string fromTypeName = significantSymbolType.name.data;
    string toTypeName = incomingSymbolType.name.data;

    return typeWillBeUpcastedTo(fromTypeName, toTypeName);
}

private bool typeWillBeUpcastedTo(string from, string to)
{
    if (auto promotionType = from in INTEGER_PROMOTIONS)
        return *promotionType == to;

    return false;
}

bool isNonConstrainedTemplate(scope ref const(DSymbol) symbolType)
{
    return symbolType.kind is CompletionKind.typeTmpParam;
}

private bool matchesWithTypeOfPointer(scope ref const(DSymbol) incomingSymbolType, scope ref const(DSymbol) significantSymbolType)
{
    return incomingSymbolType.qualifier == SymbolQualifier.pointer
        && significantSymbolType.qualifier == SymbolQualifier.pointer
        && incomingSymbolType.type is significantSymbolType.type;
}

private bool matchesWithTypeOfArray(scope ref const(DSymbol) incomingSymbolType, scope ref const(DSymbol) cursorSymbolType)
{
    return incomingSymbolType.qualifier == SymbolQualifier.array
        && cursorSymbolType.qualifier == SymbolQualifier.array
        && incomingSymbolType.type is cursorSymbolType.type;

}

private bool typeMatchesWith(scope ref const(DSymbol) incomingSymbolType, scope ref const(DSymbol) significantSymbolType) {
    return incomingSymbolType is significantSymbolType
        || isNonConstrainedTemplate(incomingSymbolType)
        || matchesWithTypeOfArray(incomingSymbolType, significantSymbolType)
        || matchesWithTypeOfPointer(incomingSymbolType, significantSymbolType)
        || willImplicitBeUpcasted(incomingSymbolType, significantSymbolType);
}

private bool matchSymbolType(const(DSymbol)* incomingSymbolType, const(DSymbol)* significantSymbolType) {

    auto currentSignificantSymbolType = significantSymbolType;
    uint numberOfRetries = 0;

    do
    {
        if (typeMatchesWith(*incomingSymbolType, *currentSignificantSymbolType)){
            return true;
        }

        if (currentSignificantSymbolType.aliasThisSymbols.empty || currentSignificantSymbolType is currentSignificantSymbolType.aliasThisSymbols.front){
            return false;
        }

        numberOfRetries++;
        // For now we are only resolving the first alias this symbol
        // when multiple alias this are supported, we can rethink another solution
        currentSignificantSymbolType = currentSignificantSymbolType.aliasThisSymbols.front.type;
    }
    while(numberOfRetries <= MAX_NUMBER_OF_MATCHING_RUNS);
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
bool isCallableWithArg(const(DSymbol)* incomingSymbol, const(DSymbol)* beforeDotType, bool isGlobalScope = false)
{
    if (incomingSymbol is null
        || beforeDotType is null
        || isGlobalScope && incomingSymbol.protection is tok!"private") // don't show private functions if we are in global scope
    {
        return false;
    }

    if (incomingSymbol.kind is CompletionKind.functionName && !incomingSymbol.functionParameters.empty && incomingSymbol.functionParameters.front.type)
    {
        return matchSymbolType(incomingSymbol.functionParameters.front.type, beforeDotType);
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
