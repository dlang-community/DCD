module dcd.server.lib;

import std.string: fromStringz;

import core.runtime;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import core.stdc.ctype;
import core.stdc.stdarg;

import dcd.common.messages;
import dcd.server.autocomplete;

import dsymbol.modulecache;

__gshared:

ModuleCache cache;

extern(C) export void dcd_init(string[] importPaths)
{
    rt_init();
    cache.addImportPaths(importPaths);
}

extern(C) export void dcd_add_imports(string[] importPaths)
{
    cache.addImportPaths(importPaths);
}

extern(C) export void dcd_clear()
{
    cache.clear();
}

extern(C) export AutocompleteResponse dcd_complete(const(char)* content, int position)
{
    AutocompleteRequest request;
    request.fileName = "stdin";
    request.cursorPosition = position;
    request.kind |= RequestKind.autocomplete;
    request.sourceCode = cast(ubyte[]) fromStringz(content);

    auto ret = complete(request, cache);
    return ret;
}

struct DSymbolInfo
{
    string name;
    ubyte kind;
    size_t[2] range;
    DSymbolInfo[] children;
}

extern(C) export DSymbolInfo[] dcd_document_symbols(const(char)* content)
{
    import containers.ttree : TTree;
    import containers.hashset;
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

    DSymbolInfo[] ret;

    AutocompleteRequest request;
    request.fileName = "stdin";
    request.cursorPosition = 0;
    request.kind |= RequestKind.autocomplete;
    request.sourceCode = cast(ubyte[]) fromStringz(content);

    LexerConfig config;
    config.fileName = "";
    auto sc = StringCache(request.sourceCode.length.optimalBucketCount);
    auto tokenArray = getTokensForParser(cast(ubyte[]) request.sourceCode, config, &sc);
    RollbackAllocator rba;
    auto pair = generateAutocompleteTrees(tokenArray, &rba, -1, cache);
    scope(exit) pair.destroy();


    void check(DSymbol* it, ref int p, DSymbolInfo* info)
    {
        //for (int i = 0; i < p; i++)
        //fprintf(stderr, " ");
        //fprintf(stderr, "loc: %ld k: %c sym: %.*s\n", it.location, cast(char) it.kind, it.name.length, it.name.ptr);

        p += 1;

        info.name = it.name;
        info.range[0] = it.location;

        if (it.location_end == 0)
            info.range[1] = it.location + it.name.length;
        else
            info.range[1] = it.location_end;
        info.kind = it.kind;

        foreach(sym; it.opSlice())
        {
            if (sym.symbolFile != "stdin") continue;

            DSymbolInfo child;
            check(sym, p, &child);
            info.children ~= child;
       }
       p -= 1;
    }

    int pos = 0;
    foreach (symbol; pair.scope_.symbols)
    {
        if (symbol.symbolFile != "stdin") continue;
        DSymbolInfo info;
        check(symbol, pos, &info);
        ret ~= info;
    }

    return ret;
}

struct Location
{
    string path;
    size_t position;
}

extern(C) export Location[] dcd_definition(const(char)* content, int position)
{
    import containers.ttree : TTree;
    import containers.hashset;
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

    AutocompleteRequest request;
    request.fileName = "stdin";
    request.cursorPosition = position;
    request.kind |= RequestKind.autocomplete;
    request.sourceCode = cast(ubyte[]) fromStringz(content);

    RollbackAllocator rba;
    auto sc = StringCache(request.sourceCode.length.optimalBucketCount);
    SymbolStuff stuff = getSymbolsForCompletion(request, CompletionType.location,
        &rba, sc, cache);
    scope(exit) stuff.destroy();

    Location[] ret;
    if (stuff.symbols.length > 0)
    {
        foreach(sym; stuff.symbols)
        {
            //fprintf(stderr, "found: %.*s  at: %.*s -> %lu\n", sym.name.length, sym.name.ptr, sym.symbolFile.length, sym.symbolFile.ptr, sym.location);
            ret ~= Location(sym.symbolFile, sym.location);
        }
    }
    return ret;
}
