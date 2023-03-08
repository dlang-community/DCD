module dsymbol.ufcs;

import dsymbol.symbol;
import dsymbol.scope_;
import std.functional : unaryFun;
import std.algorithm;
import std.array;
import std.range;
import dsymbol.builtin.names;
import std.string;
import dparse.lexer : tok;
import std.regex;
import containers.hashset : HashSet;

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

// Check if beforeDotSymbol is null or void
bool isInvalidForUFCSCompletion(const(DSymbol)* beforeDotSymbol)
{
    return beforeDotSymbol is null
        || beforeDotSymbol.name is getBuiltinTypeName(tok!"void")
        || (beforeDotSymbol.type !is null && beforeDotSymbol.type.name is getBuiltinTypeName(
                tok!"void"));
}
/**
 * Get symbols suitable for UFCS.
 *
 * a symbol is suitable for UFCS if it satisfies the following:
 * $(UL
 *  $(LI is global or imported)
 *  $(LI is callable with $(D beforeDotSymbol) as it's first argument)
 * )
 *
 * Params:
 *     completionScope = current scope
 *     beforeDotSymbol = the symbol before the dot (implicit first argument to UFCS function)
 *     cursorPosition = current position
 * Returns:
 *     callable an array of symbols suitable for UFCS at $(D cursorPosition)
 */
DSymbol*[] getSymbolsForUFCS(Scope* completionScope, const(DSymbol)* beforeDotSymbol, size_t cursorPosition)
{
    if (beforeDotSymbol.isInvalidForUFCSCompletion)
    {
        return null;
    }

    Scope* currentScope = completionScope.getScopeByCursor(cursorPosition);
    assert(currentScope);
    HashSet!size_t visited;

    // local appender
    FilteredAppender!(a => a.isCallableWithArg(beforeDotSymbol), DSymbol*[]) localAppender;

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
                sym.type.getParts(internString(null), localAppender, visited);
        }

        currentScope = currentScope.parent;
    }

    // global appender
    FilteredAppender!(a => a.isCallableWithArg(beforeDotSymbol, true), DSymbol*[]) globalAppender;

    // global symbols and global imports
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
    return localAppender.opSlice ~ globalAppender.opSlice;
}

bool willImplicitBeUpcasted(string from, string to)
{
    string* found = from in INTEGER_PROMOTIONS;
    if (!found)
    {
        return false;
    }

    return INTEGER_PROMOTIONS[from] == to;
}

bool matchAliasThis(const(DSymbol)* beforeDotType, const(DSymbol)* incomingSymbol, int recursionDepth)
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
bool isCallableWithArg(const(DSymbol)* incomingSymbol, const(DSymbol)* beforeDotType, bool isGlobalScope = false, int recursionDepth = 0)
{
    if (!incomingSymbol || !beforeDotType
        || (isGlobalScope && incomingSymbol.protection == tok!"private") || recursionDepth > MAX_RECURSION_DEPTH)
    {
        return false;
    }

    if (incomingSymbol.kind == CompletionKind.functionName && !incomingSymbol
        .functionParameters.empty)
    {
        return beforeDotType is incomingSymbol.functionParameters.front.type
            || willImplicitBeUpcasted(beforeDotType.name, incomingSymbol
                    .functionParameters.front.type.name)
            || matchAliasThis(beforeDotType, incomingSymbol, recursionDepth);

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

void getUFCSParenCompletion(ref DSymbol*[] symbols, Scope* completionScope, istring firstToken, istring nextToken, size_t cursorPosition)
{
    DSymbol* firstSymbol = completionScope.getFirstSymbolByNameAndCursor(
        firstToken, cursorPosition);

    if (firstSymbol is null)
        return;

    DSymbol*[] possibleUFCSSymbol = completionScope.getSymbolsByNameAndCursor(
        nextToken, cursorPosition);
    foreach (nextSymbol; possibleUFCSSymbol)
    {
        if (nextSymbol && nextSymbol.functionParameters)
        {
            if (nextSymbol.isCallableWithArg(firstSymbol.type))
            {
                nextSymbol.kind = CompletionKind.ufcsName;
                symbols ~= nextSymbol;
            }
        }
    }
}

unittest
{
    assert(!willImplicitBeUpcasted("A", "B"));
    assert(willImplicitBeUpcasted("bool", "int"));
}
