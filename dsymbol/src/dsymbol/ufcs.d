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
import std.typecons : nullable, Nullable;

alias SortedTokens = SortedRange!(const(Token)[], "a < b");
struct ScopeLookupContext
{
    Scope* completionScope;
    const(Token)[] exprTokens;
    size_t cursorPosition;
    const(DSymbol)* getSymbolByName(string name)
    {
        return completionScope.getFirstSymbolByNameAndCursor(istring(name), cursorPosition);
    }
}

bool compatibleType(DSymbol* sym, ref const(Token) argToken, ScopeLookupContext scopeComplentionContext)
{
    if (!sym.type)
    {
        return false;
    }

    switch (argToken.type)
    {
        mixin(STRING_LITERAL_CASES);
        return sym.type.name == "string";
    case tok!"true":
    case tok!"false":
        return sym.type.name is getBuiltinTypeName(tok!"bool");

    case tok!"intLiteral":
    case tok!"longLiteral":
    case tok!"uintLiteral":
    case tok!"ulongLiteral":
        // integer literals
        return 
            // integers
            sym.type.name is getBuiltinTypeName(tok!"int") ||
            sym.type.name is getBuiltinTypeName(tok!"uint") ||
            sym.type.name is getBuiltinTypeName(tok!"long") ||
            sym.type.name is getBuiltinTypeName(tok!"ulong") ||
            sym.type.name is getBuiltinTypeName(tok!"byte") ||
            sym.type.name is getBuiltinTypeName(tok!"ubyte") ||
            sym.type.name is getBuiltinTypeName(tok!"short") ||
            sym.type.name is getBuiltinTypeName(tok!"ushort") ||

             // floats
            sym.type.name is getBuiltinTypeName(tok!"float") ||
            sym.type.name is getBuiltinTypeName(tok!"double") ||
            sym.type.name is getBuiltinTypeName(tok!"real") ||

             // complex
            sym.type.name is getBuiltinTypeName(tok!"cfloat") ||
            sym.type.name is getBuiltinTypeName(tok!"cdouble") ||
            sym.type.name is getBuiltinTypeName(tok!"creal");

    case tok!"floatLiteral":
    case tok!"doubleLiteral":
    case tok!"realLiteral":
        return 
            // floats
            sym.type.name is getBuiltinTypeName(tok!"float") ||
            sym.type.name is getBuiltinTypeName(tok!"double") ||
            sym.type.name is getBuiltinTypeName(tok!"real") ||

            sym.type.name is getBuiltinTypeName(tok!"cfloat") ||
            sym.type.name is getBuiltinTypeName(tok!"cdouble") ||
            sym.type.name is getBuiltinTypeName(tok!"creal");

    case tok!"ifloatLiteral":
    case tok!"idoubleLiteral":
    case tok!"irealLiteral":
        // imaginary literals
        return 
            // imaginary
            sym.type.name is getBuiltinTypeName(tok!"ifloat") ||
            sym.type.name is getBuiltinTypeName(tok!"idouble") ||
            sym.type.name is getBuiltinTypeName(tok!"ireal") ||

             // complex
            sym.type.name is getBuiltinTypeName(tok!"cfloat") ||
            sym.type.name is getBuiltinTypeName(tok!"cdouble") ||
            sym.type.name is getBuiltinTypeName(tok!"creal");

    default:
        // Not a primitive type eg. Identifier
        // Doing type looking up 
        if (argToken.text)
        {
            auto found = scopeComplentionContext.getSymbolByName(argToken.text);
            if (found)
            {
                return sym.type is found.type;
            }
        }
        return false;
    }
}

struct ExpressionInfo
{
    const(DSymbol)* type;
    const(Token)* significantToken;
    bool assumingLvalue; // We only assume else we need to do life time analysis.
    bool isFromFunction;
    const(Token)[] arguments;
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

private const(Token)* findUFCSBaseToken(const(Token)[] tokens, out const(Token)[] arguments)
{
    if (tokens.empty)
        return null;

    int depth = 0;

    // Walk backwards to skip nested parentheses/brackets/braces
    for (size_t i = tokens.length; i-- > 0;)
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
            // An unmatched opener (e.g. the leading `(` of a call whose
            // `)` lies after the cursor): the expression cannot extend
            // past it. Without this, depth goes negative and every
            // remaining token is skipped as "nested", so the base token
            // lookup fails and the whole receiver type deduction aborts.
            if (depth == 0)
                return &tokens[i + 1];
            depth--;
            continue;
        }

        if (depth != 0)
            continue;

        // If we hit a literal or identifier, that's likely our base
        if (isStringLiteral(t) || t is tok!"intLiteral" || t is tok!"floatLiteral")
        {
            return &tokens[i];
        }
        if (t is tok!"identifier")
        {
            // If this is a function call, then extract the arguments
            if (tokens.length >= 2 && i + 1 < tokens.length && tokens[i + 1] == tok!"(" && tokens[$ - 1] == tok!")")
            {
                auto argTokens = tokens[i + 2 .. $ - 1]; // get whats inside ( ... )
                foreach (argToken; argTokens)
                {
                    if (argToken == tok!",")
                    {
                        continue;
                    }
                    arguments ~= argToken;
                }
            }
            return &tokens[i];
        }

        // A leading `*` is a pointer DEREFERENCE, not the multiplication
        // operator: `(*p).func` has `p` as its base. Keep walking so the
        // identifier under the deref is found.
        if (t is tok!"*")
            continue;

        // Stop at anything else that breaks the expression (operators,
        // keywords, etc.). The stop token can be the LAST token of the
        // slice (e.g. the `int` of `Foo!int` after paren stripping) —
        // returning one past it would be out of bounds.
        return i + 1 < tokens.length ? &tokens[i + 1] : &tokens[i];
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

/// Resolves a symbol in a UFCS chain during type deduction.
/// This is intentionally permissive (name-based lookup)
/// Used only for type deduction, completion filtering will be done in a later step
private const(DSymbol)* resolveUFCSChainSymbol(
    Scope* completionScope,
    ExpressionInfo beforeDotType,
    istring name,
    size_t cursorPosition)
{
    Appender!(DSymbol*[]) local;
    Appender!(DSymbol*[]) global;

    getUFCSSymbols(local, global, completionScope, cursorPosition);

    auto allSymbols = local.data ~ global.data;

    const(DSymbol)* fallback = null;

    foreach (sym; allSymbols)
    {
        if (sym.name != name)
        {
            continue;
        }
        // Prefer a symbol that actually matches the type
        if (sym.isCallableWithArg(beforeDotType))
        {
            return sym;
        }

        // Otherwise remember a fallback (loose match)
        if (fallback is null)
        {
            fallback = sym;
        }
    }

    return fallback;
}

/**
 * If `significantToken` is the last identifier of a plain member-access
 * chain (`a.b.c`), returns the index of that identifier within `exprTokens`.
 * The chain prefix must be exactly `identifier ('.' identifier)*`, so the
 * index is even and at least 2. Returns 0 for anything else (no prefix,
 * calls, indexings, keywords, literals).
 */
private size_t memberChainBaseIndex(const(Token)[] exprTokens,
    const(Token)* significantToken)
{
    size_t sigIndex = size_t.max;
    foreach (size_t i; 0 .. exprTokens.length)
    {
        if (&exprTokens[i] is significantToken)
        {
            sigIndex = i;
            break;
        }
    }
    if (sigIndex == size_t.max || sigIndex < 2 || sigIndex % 2 != 0)
        return 0;
    if (exprTokens[sigIndex].type !is tok!"identifier")
        return 0;
    foreach (size_t i; 0 .. sigIndex)
    {
        if (i % 2 == 0)
        {
            if (exprTokens[i].type !is tok!"identifier")
                return 0;
        }
        else if (exprTokens[i].type !is tok!".")
            return 0;
    }
    return sigIndex;
}

/**
 * Resolves the type of the member-access chain `exprTokens[0 .. chainEnd]`
 * (`a.b.c`, `chainEnd` = index of the last identifier) by looking up the
 * first identifier in scope and following each `.name` link through the
 * members of the current symbol's type. Returns null if any link cannot
 * be resolved.
 */
private const(DSymbol)* resolveMemberChainType(Scope* completionScope,
    const(Token)[] exprTokens, size_t chainEnd, size_t cursorPosition)
{
    auto symbols = completionScope.getSymbolsByNameAndCursor(
        istring(exprTokens[0].text), cursorPosition);
    if (symbols.empty)
        return null;

    const(DSymbol)* current = symbols.front;
    for (size_t i = 1; i <= chainEnd; i += 2)
    {
        current = unwrapToValueSymbol(current);
        // Variables and parameters carry their members on their type.
        if (current is null || current.type is null || current.type is current)
            return null;
        auto parts = current.type.getPartsByName(istring(exprTokens[i + 1].text));
        if (parts.empty)
            return null;
        current = parts.front;
    }
    current = unwrapToValueSymbol(current);
    if (current is null || current.type is null || current.type is current)
        return null;
    return current.type;
}

/// Unwraps function/alias/import symbols to the value symbol they denote.
private const(DSymbol)* unwrapToValueSymbol(const(DSymbol)* symbol)
{
    while (symbol !is null
        && (symbol.qualifier == SymbolQualifier.func
            || symbol.kind == CompletionKind.functionName
            || symbol.kind == CompletionKind.importSymbol
            || symbol.kind == CompletionKind.aliasName))
    {
        if (symbol.type is null || symbol.type is symbol)
            break;
        symbol = symbol.type;
    }
    return symbol;
}

private Nullable!ExpressionInfo deduceExpressionType(
    Scope* completionScope,
    const(Token)[] exprTokens,
    size_t cursorPosition)
{
    ExpressionInfo info;

    if (exprTokens.empty)
    {
        return Nullable!ExpressionInfo.init;
    }

    // A parenthesized receiver (`(*p).func`): the base of the expression
    // is INSIDE the parens, but the backward walk below treats them as
    // nested scopes to skip over, so it would never reach the identifier.
    // Strip balanced outer parens first (mirroring the chain resolver's
    // `tokens[0] == tok!"("` handling).
    while (exprTokens.length >= 2
        && exprTokens[0].type is tok!"("
        && exprTokens[$ - 1].type is tok!")")
    {
        // Only strip when the parens actually wrap the WHOLE expression:
        // the '(' at 0 must match the ')' at the end.
        int depth = 0;
        bool wrapsWhole;
        foreach (i, t; exprTokens)
        {
            if (t.type is tok!"(")
                depth++;
            else if (t.type is tok!")")
            {
                depth--;
                if (depth == 0 && i == exprTokens.length - 1)
                    wrapsWhole = true;
            }
        }
        if (!wrapsWhole)
            break;
        exprTokens = exprTokens[1 .. $ - 1];
        if (exprTokens.empty)
            return Nullable!ExpressionInfo.init;
    }

    info.significantToken = findUFCSBaseToken(exprTokens, info.arguments);
    if (isStringLiteral(info.significantToken.type))
    {
        info.type = completionScope.getFirstSymbolByNameAndCursor(
            symbolNameToTypeName(STRING_LITERAL_SYMBOL_NAME), cursorPosition);
        return nullable(info);
    }

    auto scopeLookupContext = ScopeLookupContext(completionScope, exprTokens, cursorPosition);
    info.type = deduceSymbolTypeByToken(info, scopeLookupContext);

    // The left→right walk below starts right after the base token.
    size_t walkStart = 1;

    if (info.type is null)
    {
        // The base identifier is not a scope-level name: it is the last
        // segment of a member-access chain (`ctx.vertexBuffer` in
        // `ctx.vertexBuffer.func()`), where `vertexBuffer` is a member and
        // only the first segment (`ctx`) is visible in scope. Resolve the
        // chain from its first identifier by following members — the same
        // traversal the main chain resolver (getSymbolsByTokenChain)
        // performs.
        immutable size_t chainEnd = memberChainBaseIndex(exprTokens,
            info.significantToken);
        if (chainEnd == 0)
            return Nullable!ExpressionInfo.init;
        info.type = resolveMemberChainType(completionScope, exprTokens,
            chainEnd, cursorPosition);
        if (info.type is null)
            return Nullable!ExpressionInfo.init;
        // The chain up to and including the base identifier is already
        // resolved; the walk must not re-process those tokens (its dot
        // handler resolves UFCS chain links in scope, not members).
        walkStart = chainEnd + 1;
    }

    // A leading `*` is a pointer DEREFERENCE (`(*p).func`): the receiver
    // is the pointer's target, not the pointer itself. Unwrap one pointer
    // layer so a `void func(Foo)` matches a `(*p).func` call.
    if (exprTokens.length >= 2
        && exprTokens[0].type is tok!"*"
        && info.type.qualifier == SymbolQualifier.pointer
        && info.type.type !is null)
    {
        info.type = info.type.type;
    }

    // A leading `*` is a pointer DEREFERENCE (`(*p).func`): the receiver
    // is the pointer's target, not the pointer itself. Unwrap one pointer
    // layer so a `void func(Foo)` matches a `(*p).func` call.
    if (exprTokens.length >= 2
        && exprTokens[0].type is tok!"*"
        && info.type.qualifier == SymbolQualifier.pointer
        && info.type.type !is null)
    {
        info.type = info.type.type;
    }

    // 2. Walk through the expression left → right
    for (size_t i = walkStart; i < exprTokens.length; i++)
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
            if (info.type !is null && info.type.type !is null)
            {
                info.type = info.type.type;
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

            auto match = resolveUFCSChainSymbol(
                completionScope,
                info,
                name,
                cursorPosition
            );

            if (match is null)
            {
                return Nullable!ExpressionInfo.init;
            }

            i++; // skip identifier
            continue;
        }
    }
    return nullable(info);
}

private const(DSymbol)* deduceSymbolTypeByToken(ref ExpressionInfo info, ScopeLookupContext scopeCompletionContext)
{
    const(DSymbol)* symbol = null;
    auto found = scopeCompletionContext.completionScope.getSymbolsByNameAndCursor(
        istring(info.significantToken.text), scopeCompletionContext.cursorPosition);

    if (found.empty)
    {
        return null;
    }

    if (found.length == 1)
    {
        symbol = found.front;
    }
    else if (found.length > 1)
    {
        // If we have more functions then we must have overloaded function 
        if (info.arguments.length > 0)
        {
            // we need to match with the arguments accordingly if any
            // we assume that the first param matches since it's a UFCS call, hence why we - 1.
            auto filtered = found.find!((i => max(i.functionParameters.length - 1, 0) == info
                    .arguments.length));
            if (filtered.length == 1)
            {
                // There is only 1 solution
                symbol = filtered.front;
            }
            else if (filtered.length > 1)
            {
                bool allMatch = false;
                foreach (DSymbol* sym; filtered)
                {
                    allMatch = false;
                    foreach (idx, p; sym.functionParameters[1 .. $]) // we assume that the first param matches since it's a UFCS call, hence why we start with 1.
                    {
                        allMatch = compatibleType(p, info.arguments[idx], scopeCompletionContext);
                        if (!allMatch)
                        {
                            trace(sym.name," doesn't match with the arguments");
                            break;
                        }
                    }
                    if (allMatch)
                    {
                        symbol = sym;
                        trace("Found the right overloaded function ", sym.type.name);
                        return sym.type;
                    }
                }
            }
        }
    }

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
            || symbolType.type is symbolType) // special case for string
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

    for (size_t i = tokens.length; i-- > 0;)
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
            if (depth > 0)
            {
                // Matches a closing token we skipped over earlier.
                depth--;
                continue;
            }
            // An unmatched opener (e.g. the `{` of the enclosing function
            // body): the expression cannot extend past it. Without this,
            // depth goes negative and every remaining token is skipped as
            // "nested", swallowing the whole file prefix.
            return &tokens[i + 1];
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

        // Also allowing ) for ufcs function chaining
        if (slicedAtParen.length >= 3
            && slicedAtParen[$ - 3].type is tok!"."
            && slicedAtParen[$ - 2].type is tok!"identifier"
            && slicedAtParen[$ - 1].type is tok!"(")
        {
            // Trim the receiver down to the actual expression, the same way
            // dot completion does. Otherwise the raw prefix (which can
            // include earlier statements or even the module's `import`
            // declarations) is treated as one long UFCS chain, and the type
            // deduction aborts as soon as one link (e.g. the `.` of
            // `import std.stdio;`) can't be resolved.
            const(Token)* exprStart = findUFCSExpressionStart(slicedAtParen[0 .. $ - 3]);

            if (exprStart is null)
                return tokenCursorResult;

            tokenCursorResult.expressionTokens = exprStart[0 .. &slicedAtParen[$ - 3] - exprStart];
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

    Nullable!ExpressionInfo deducedSymbolType = deduceExpressionType(completionScope, tokenCursorResult
            .expressionTokens, cursorPosition);

    if (deducedSymbolType.isNull)
    {
        return [];
    }

    if (deducedSymbolType.get().type.isInvalidForUFCSCompletion)
    {
        trace("CursorSymbolType isn't valid for UFCS completion");
        return [];
    }

    if (tokenCursorResult.completionContext == CompletionContext.ParenCompletion)
    {
        return getUFCSSymbolsForParenCompletion(deducedSymbolType.get(), completionScope, tokenCursorResult
                .functionName, cursorPosition);
    }
    else
    {
        return getUFCSSymbolsForDotCompletion(deducedSymbolType.get(), completionScope, cursorPosition, tokenCursorResult
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

    return rankByConstraint(localAppender.data ~ globalAppender.data, symbolType.type);
}

private DSymbol*[] getUFCSSymbolsForParenCompletion(ExpressionInfo symbolType, Scope* completionScope, istring searchWord, size_t cursorPosition)
{
    // local appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType) && a.name.among(searchWord), DSymbol*[]) localAppender;
    // global appender
    FilteredAppender!(a => a.isCallableWithArg(symbolType, true) && a.name.among(searchWord), DSymbol*[]) globalAppender;

    getUFCSSymbols(localAppender, globalAppender, completionScope, cursorPosition);

    return rankByConstraint(localAppender.data ~ globalAppender.data, symbolType.type);

}

/**
 * Ranks same-named template overloads by their constraint: overloads whose
 * `is(T == X)` constraint matches the receiver's kind come first, ones that
 * provably don't match go last. Overloads without (recognizable)
 * constraints keep their relative order in between. This is a reordering
 * only — nothing is removed, so a wrong guess can't hide the right answer.
 */
private DSymbol*[] rankByConstraint(DSymbol*[] symbols, const(DSymbol)* receiverType)
{
    import dsymbol.utils : matchConstraint, ConstraintMatch;

    if (receiverType is null || symbols.length < 2)
        return symbols;

    // Only worth ranking when several symbols share a name.
    bool hasOverloads;
    outer: foreach (i, sym; symbols[0 .. $ - 1])
    {
        foreach (other; symbols[i + 1 .. $])
        {
            if (sym.name is other.name)
            {
                hasOverloads = true;
                break outer;
            }
        }
    }
    if (!hasOverloads)
        return symbols;

    // Stable three-way partition: match > unknown > noMatch.
    DSymbol*[] matched;
    DSymbol*[] unknown;
    DSymbol*[] rejected;
    foreach (sym; symbols)
    {
        final switch (matchConstraint(sym, receiverType))
        {
        case ConstraintMatch.match:
            matched ~= sym;
            break;
        case ConstraintMatch.unknown:
            unknown ~= sym;
            break;
        case ConstraintMatch.noMatch:
            rejected ~= sym;
            break;
        }
    }
    return matched ~ unknown ~ rejected;
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

private bool matchStringLikeTypes(scope ref const(DSymbol) incomingSymbolType, scope ref const(
        DSymbol) significantSymbolType)
{
    if ((incomingSymbolType.name.data == "string" || incomingSymbolType.name.data == "wstring"
            || incomingSymbolType.name.data == "dstring") && (significantSymbolType.name.data == "string" || significantSymbolType
            .name.data == "wstring"
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
        || matchStringLikeTypes(incomingSymbolType, significantSymbolType)
        // The same type can be represented by two different DSymbol
        // instances: one from the analyzed ("stdin") document's tree and
        // one from the cached on-disk module an imported function's
        // parameter resolves through. Pointer equality above fails for
        // those, so fall back to comparing the type names (both must be
        // user-defined aggregate types; builtins are covered by the
        // pointer-equal builtin trees).
        || (isUserDefinedAggregate(incomingSymbolType)
            && isUserDefinedAggregate(significantSymbolType)
            && incomingSymbolType.name == significantSymbolType.name);

}

/// Whether `symbol` is a user-defined struct/class/union/interface type
/// (as opposed to a builtin, variable, function, alias, etc.).
private bool isUserDefinedAggregate(scope ref const(DSymbol) symbol)
{
    return symbol.kind == CompletionKind.className
        || symbol.kind == CompletionKind.interfaceName
        || symbol.kind == CompletionKind.structName
        || symbol.kind == CompletionKind.unionName;
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
            break;
        }

        numberOfRetries++;
        // For now we are only resolving the first alias this symbol
        // when multiple alias this are supported, we can rethink another solution
        currentSignificantSymbolType = currentSignificantSymbolType.aliasThisSymbols.front.type;
    }
    while (numberOfRetries <= MAX_NUMBER_OF_MATCHING_RUNS);

    // A receiver of a derived class implicitly converts to any of its base
    // classes / interfaces, so a UFCS function taking a base type is callable
    // on it. This does NOT apply to `ref`/`out` parameters: D requires the
    // exact type there (a `ref B` cannot bind a `C` lvalue).
    // resolveInheritance adds an IMPORT_SYMBOL_NAME child pointing at each
    // base symbol, so walk up the chain (cycle-guarded).
    if (firstParameter.parameterIsRef || firstParameter.parameterIsOut)
        return false;
    return matchesWithBaseClass(firstParameter, significantSymbolType);
}

/**
 * Returns: `true` if `firstParameter.type` matches any base class or
 * interface of `significantSymbolType` (transitively).
 */
private bool matchesWithBaseClass(const(DSymbol)* firstParameter, const(DSymbol)* significantSymbolType)
{
    import dsymbol.builtin.names : IMPORT_SYMBOL_NAME;

    // getPartsByName auto-dereferences pointers (member-completion
    // semantics), but a T* receiver does NOT implicitly convert to anything
    // T converts to when passed as a UFCS argument (e.g. an alias-this
    // target or a base class of T). Stop before the walk.
    if (significantSymbolType.qualifier == SymbolQualifier.pointer)
        return false;

    // resolveInheritance adds one IMPORT_SYMBOL_NAME child per base class /
    // interface. getPartsByName follows those children transitively, so this
    // is the full ancestor set (cycle-safe via its visited set).
    foreach (base; significantSymbolType.getPartsByName(IMPORT_SYMBOL_NAME))
    {
        if (base.type is null)
            continue;
        if (typeMatchesWith(*firstParameter.type, *base.type))
            return true;
    }
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

    if (incomingSymbol.kind is CompletionKind.functionName && !incomingSymbol.functionParameters.empty)
    {
        auto firstParam = incomingSymbol.functionParameters.front;
        if (firstParam.type)
            return matchSymbolType(firstParam, beforeDotType.type);
        // Parameter types of cached modules can stay unresolved when the
        // declaring module is part of a circular import chain: the type's
        // module was still being cached when the parameter was processed,
        // so only the recorded type name (typeSymbolName) remains. Fall
        // back to comparing it with the receiver's type name.
        if (firstParam.typeSymbolName !is null && beforeDotType.type !is null)
            return firstParam.typeSymbolName == beforeDotType.type.name;
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
