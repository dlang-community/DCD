module dcd.server.autocomplete.ufcs;

import dcd.server.autocomplete.util;
import dsymbol.symbol;
import dsymbol.scope_;
import dcd.common.messages;
import std.functional : unaryFun;
import std.algorithm;
import std.array;
import std.range;
import dsymbol.builtin.names;
import std.string;
import dparse.lexer : tok;
import std.regex;
import dcd.server.autocomplete.calltip_utils;
import containers.hashset : HashSet;
import std.experimental.logger;

void lookupUFCS(Scope* completionScope, DSymbol* beforeDotSymbol, size_t cursorPosition, ref AutocompleteResponse response)
{
    // UFCS completion
    DSymbol*[] ufcsSymbols = getSymbolsForUFCS(completionScope, beforeDotSymbol, cursorPosition);

    foreach (const symbol; ufcsSymbols)
    {
        // Filtering only those that match with type of the beforeDotSymbol
        // We use the calltip since we need more data from dsymbol
        // hopefully this is solved in the future
        if (getFirstArgumentOfFunction(symbol.callTip) == beforeDotSymbol.name)
        {
            response.completions ~= createCompletionForUFCS(symbol);
        }
    }
}

AutocompleteResponse.Completion createCompletionForUFCS(const DSymbol* symbol)
{
    return AutocompleteResponse.Completion(symbol.name, symbol.kind, removeFirstArgumentOfFunction(
                symbol.callTip), symbol
            .symbolFile, symbol
            .location, symbol
            .doc);
}

/**
 * Get symbols suitable for UFCS.
 *
 * a symbol is suitable for UFCS if it satisfies the following:
 * $(UL
 *  $(LI is global or imported)
 *  $(LI is callable with $(D implicitArg) as it's first argument)
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
    assert(beforeDotSymbol);

    if (beforeDotSymbol.name is getBuiltinTypeName(tok!"void")
        || (beforeDotSymbol.type !is null
            && beforeDotSymbol.type.name is getBuiltinTypeName(tok!"void")))
    {

        return null; // no UFCS for void
    }

    Scope* currentScope = completionScope.getScopeByCursor(cursorPosition);
    assert(currentScope);
    HashSet!size_t visited;
    // local imports only
    FilteredAppender!(a => a.isCallableWithArg(beforeDotSymbol), DSymbol*[]) app;
    while (currentScope !is null && currentScope.parent !is null)
    {
        auto localImports = currentScope.symbols.filter!(a => a.kind == CompletionKind.importSymbol);
        foreach (sym; localImports)
        {
            if (sym.type is null)
                continue;
            if (sym.qualifier == SymbolQualifier.selectiveImport)
                app.put(sym.type);
            else
                sym.type.getParts(internString(null), app, visited);
        }

        currentScope = currentScope.parent;
    }
    // global symbols and global imports
    assert(currentScope !is null);
    assert(currentScope.parent is null);
    foreach (sym; currentScope.symbols)
    {
        if (sym.kind != CompletionKind.importSymbol)
            app.put(sym);
        else if (sym.type !is null)
        {
            if (sym.qualifier == SymbolQualifier.selectiveImport)
                app.put(sym.type);
            else
                sym.type.getParts(internString(null), app, visited);
        }
    }
    return app.data;
}

/**
   Params:
   symbol = the symbol to check
   arg0 = the argument
   Returns:
   true if if $(D symbol) is callable with $(D arg0) as it's first argument
   false otherwise
*/
bool isCallableWithArg(const(DSymbol)* symbol, const(DSymbol)* arg0)
{
    // FIXME: do signature type checking?
    // 	a lot is to be done in dsymbol for type checking to work.
    //  for instance, define an isSbtype function for where it is applicable
    // 	ex: interfaces, subclasses, builtintypes ...

    // FIXME: instruct dsymbol to always save paramater symbols
    // 	 and check these instead of checking callTip

    static bool checkCallTip(string callTip)
    {
        assert(callTip.length);
        if (callTip.endsWith("()"))
            return false; // takes no arguments
        else if (callTip.endsWith("(...)"))
            return true;
        else
            return true; // FIXME: assume yes?
    }

    assert(symbol);
    assert(arg0);

    switch (symbol.kind)
    {
    case CompletionKind.dummy:
        if (symbol.qualifier == SymbolQualifier.func)
            return checkCallTip(symbol.callTip);
        break;
    case CompletionKind.importSymbol:
        if (symbol.type is null)
            break;
        if (symbol.qualifier == SymbolQualifier.selectiveImport)
            return symbol.type.isCallableWithArg(arg0);
        break;
    case CompletionKind.structName:
        foreach (constructor; symbol.getPartsByName(CONSTRUCTOR_SYMBOL_NAME))
        {
            // check user defined contructors or auto-generated constructor
            if (checkCallTip(constructor.callTip))
                return true;
        }
        break;
    case CompletionKind.variableName:
    case CompletionKind.enumMember: // assuming anonymous enum member
        if (symbol.type !is null)
        {
            if (symbol.type.qualifier == SymbolQualifier.func)
                return checkCallTip(symbol.type.callTip);
            foreach (functor; symbol.type.getPartsByName(internString("opCall")))
                if (checkCallTip(functor.callTip))
                    return true;
        }
        break;
    case CompletionKind.functionName:
        return checkCallTip(symbol.callTip);
    case CompletionKind.enumName:
    case CompletionKind.aliasName:
        if (symbol.type !is null && symbol.type !is symbol)
            return symbol.type.isCallableWithArg(arg0);
        break;
    case CompletionKind.unionName:
    case CompletionKind.templateName:
        return true; // can we do more checks?
    case CompletionKind.withSymbol:
    case CompletionKind.className:
    case CompletionKind.interfaceName:
    case CompletionKind.memberVariableName:
    case CompletionKind.keyword:
    case CompletionKind.packageName:
    case CompletionKind.moduleName:
    case CompletionKind.mixinTemplateName:
        break;
    default:
        break;
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

bool doUFCSSearch(string beforeToken, string lastToken)
{
    // we do the search if they are different from eachother
    return beforeToken != lastToken;
}
