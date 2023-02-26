module dsymbol.tests;

import std.experimental.allocator;
import dparse.ast, dparse.parser, dparse.lexer, dparse.rollback_allocator;
import dsymbol.cache_entry, dsymbol.modulecache, dsymbol.symbol;
import dsymbol.conversion, dsymbol.conversion.first, dsymbol.conversion.second;
import dsymbol.semantic, dsymbol.string_interning, dsymbol.builtin.names;
import std.file, std.path, std.format;
import std.stdio : writeln, stdout;

/**
 * Parses `source`, caches its symbols and compares the the cache content
 * with the `results`.
 *
 * Params:
 *      source = The source code to test.
 *      results = An array of string array. Each slot represents the variable name
 *      followed by the type strings.
 */
version (unittest):
void expectSymbolsAndTypes(const string source, const string[][] results,
	string file = __FILE_FULL_PATH__, size_t line = __LINE__)
{
	import core.exception : AssertError;
	import std.exception : enforce;

	ModuleCache mcache;
	auto pair = generateAutocompleteTrees(source, mcache);
	scope(exit) pair.destroy();

	size_t i;
	foreach(ss; (*pair.symbol)[])
	{
		if (ss.type)
		{
			enforce!AssertError(i <= results.length, "not enough results", file, line);
			enforce!AssertError(results[i].length > 1,
				"at least one type must be present in a result row", file, line);
			enforce!AssertError(ss.name == results[i][0],
				"expected variableName: `%s` but got `%s`".format(results[i][0], ss.name),
				file, line);

			auto t = cast() ss.type;
			foreach (immutable j; 1..results[i].length)
			{
				enforce!AssertError(t != null, "null symbol", file, line);
				enforce!AssertError(t.name == results[i][j],
					"expected typeName: `%s` but got `%s`".format(results[i][j], t.name),
					file, line);
				if (t.type is t && t.name.length && t.name[0] != '*')
					break;
				t = t.type;
			}
			i++;
		}
	}
	enforce!AssertError(i == results.length, "too many expected results, %s is left".format(results[i .. $]), file, line);
}

@system unittest
{
	writeln("Running type deduction tests...");
	q{bool b; int i;}.expectSymbolsAndTypes([["b", "bool"],["i", "int"]]);
	q{auto b = false;}.expectSymbolsAndTypes([["b", "bool"]]);
	q{auto b = true;}.expectSymbolsAndTypes([["b", "bool"]]);
	q{auto b = [0];}.expectSymbolsAndTypes([["b", "*arr-literal*", "int"]]);
	q{auto b = [[0]];}.expectSymbolsAndTypes([["b", "*arr-literal*", "*arr-literal*", "int"]]);
	q{auto b = [[[0]]];}.expectSymbolsAndTypes([["b", "*arr-literal*", "*arr-literal*", "*arr-literal*", "int"]]);
	q{auto b = [];}.expectSymbolsAndTypes([["b", "*arr-literal*", "void"]]);
	q{auto b = [[]];}.expectSymbolsAndTypes([["b", "*arr-literal*", "*arr-literal*", "void"]]);
	//q{int* b;}.expectSymbolsAndTypes([["b", "*", "int"]]);
	//q{int*[] b;}.expectSymbolsAndTypes([["b", "*arr*", "*", "int"]]);

	q{auto b = new class {int i;};}.expectSymbolsAndTypes([["b", "__anonclass1"]]);

	// got a crash before but solving is not yet working ("foo" instead of  "__anonclass1");
	q{class Bar{} auto foo(){return new class Bar{};} auto b = foo();}.expectSymbolsAndTypes([["b", "foo"]]);
}

// this one used to crash, see #125
unittest
{
	ModuleCache cache;
	auto source = q{ auto a = true ? [42] : []; };
	auto pair = generateAutocompleteTrees(source, cache);
}

// https://github.com/dlang-community/D-Scanner/issues/749
unittest
{
	ModuleCache cache;
	auto source = q{ void test() { foo(new class A {});}  };
	auto pair = generateAutocompleteTrees(source, cache);
}

// https://github.com/dlang-community/D-Scanner/issues/738
unittest
{
	ModuleCache cache;
	auto source = q{ void b() { c = } alias b this;  };
	auto pair = generateAutocompleteTrees(source, cache);
}

unittest
{
	ModuleCache cache;

	writeln("Running function literal tests...");
	const sources = [
		q{            int a;   auto dg = {     };    },
		q{ void f() { int a;   auto dg = {     };  } },
		q{ auto f =              (int a) {     };    },
		q{ auto f() { return     (int a) {     };  } },
		q{ auto f() { return   g((int a) {     }); } },
		q{ void f() {          g((int a) {     }); } },
		q{ void f() { auto x =   (int a) {     };  } },
		q{ void f() { auto x = g((int a) {     }); } },
	];
	foreach (src; sources)
	{
		auto pair = generateAutocompleteTrees(src, cache);
		auto a = pair.scope_.getFirstSymbolByNameAndCursor(istring("a"), 35);
		assert(a, src);
		assert(a.type, src);
		assert(a.type.name == "int", src);
	}
}

unittest
{
	ModuleCache cache;
	writeln("Get return type name");
	auto source = q{ int meaningOfLife() { return 42; } };
	auto pair = generateAutocompleteTrees(source, cache);
	auto meaningOfLife = pair.symbol.getFirstPartNamed(istring("meaningOfLife"));
	assert(meaningOfLife.returnType.name == "int");
}

unittest
{
	ModuleCache cache;
	writeln("Get return type name from class method");
	auto source = q{ class Life { uint meaningOfLife() { return 42; } }};
	auto pair = generateAutocompleteTrees(source, cache);
	auto lifeClass = pair.symbol.getFirstPartNamed(istring("Life"));
	auto meaningOfLife = lifeClass.getFirstPartNamed(istring("meaningOfLife"));
	assert(meaningOfLife.returnType.name == "uint");
}

unittest
{
	ModuleCache cache;

	writeln("Running struct constructor tests...");
	auto source = q{ struct A {int a; struct B {bool b;} int c;} };
	auto pair = generateAutocompleteTrees(source, cache);
	auto A = pair.symbol.getFirstPartNamed(internString("A"));
	auto B = A.getFirstPartNamed(internString("B"));
	auto ACtor = A.getFirstPartNamed(CONSTRUCTOR_SYMBOL_NAME);
	auto BCtor = B.getFirstPartNamed(CONSTRUCTOR_SYMBOL_NAME);
	assert(ACtor.callTip == "this(int a, int c)");
	assert(BCtor.callTip == "this(bool b)");
}

unittest
{
	ModuleCache cache;

	writeln("Running union constructor tests...");
	auto source = q{ union A {int a; bool b;} };
	auto pair = generateAutocompleteTrees(source, cache);
	auto A = pair.symbol.getFirstPartNamed(internString("A"));
	auto ACtor = A.getFirstPartNamed(CONSTRUCTOR_SYMBOL_NAME);
	assert(ACtor.callTip == "this(int a, bool b)");
}

unittest
{
	ModuleCache cache;
	writeln("Running non-importable symbols tests...");
	auto source = q{
		class A { this(int a){} }
		class B : A {}
		class C { A f; alias f this; }
	};
	auto pair = generateAutocompleteTrees(source, cache);
	auto A = pair.symbol.getFirstPartNamed(internString("A"));
	auto B = pair.symbol.getFirstPartNamed(internString("B"));
	auto C = pair.symbol.getFirstPartNamed(internString("C"));
	assert(A.getFirstPartNamed(CONSTRUCTOR_SYMBOL_NAME) !is null);
	assert(B.getFirstPartNamed(CONSTRUCTOR_SYMBOL_NAME) is null);
	assert(C.getFirstPartNamed(CONSTRUCTOR_SYMBOL_NAME) is null);
}

unittest
{
	ModuleCache cache;

	writeln("Running alias this tests...");
	auto source = q{ struct A {int f;} struct B { A a; alias a this; void fun() { auto var = f; };} };
	auto pair = generateAutocompleteTrees(source, cache);
	auto A = pair.symbol.getFirstPartNamed(internString("A"));
	auto B = pair.symbol.getFirstPartNamed(internString("B"));
	auto Af = A.getFirstPartNamed(internString("f"));
	auto fun = B.getFirstPartNamed(internString("fun"));
	auto var = fun.getFirstPartNamed(internString("var"));
	assert(Af is pair.scope_.getFirstSymbolByNameAndCursor(internString("f"), var.location));
}

unittest
{
	ModuleCache cache;

	writeln("Running anon struct tests...");
	auto source = q{ struct A { struct {int a;}} };
	auto pair = generateAutocompleteTrees(source, cache);
	auto A = pair.symbol.getFirstPartNamed(internString("A"));
	assert(A);
	auto Aa = A.getFirstPartNamed(internString("a"));
	assert(Aa);
}

unittest
{
	ModuleCache cache;

	writeln("Running anon class tests...");
	const sources = [
		q{            auto a =   new class Object { int i;                };    },
		q{            auto a =   new class Object { int i; void m() {   } };    },
		q{            auto a = g(new class Object { int i;                });   },
		q{            auto a = g(new class Object { int i; void m() {   } });   },
		q{ void f() {            new class Object { int i;                };  } },
		q{ void f() {            new class Object { int i; void m() {   } };  } },
		q{ void f() {          g(new class Object { int i;                }); } },
		q{ void f() {          g(new class Object { int i; void m() {   } }); } },
		q{ void f() { auto a =   new class Object { int i;                };  } },
		q{ void f() { auto a =   new class Object { int i; void m() {   } };  } },
		q{ void f() { auto a = g(new class Object { int i;                }); } },
		q{ void f() { auto a = g(new class Object { int i; void m() {   } }); } },
	];
	foreach (src; sources)
	{
		auto pair = generateAutocompleteTrees(src, cache);
		auto a = pair.scope_.getFirstSymbolByNameAndCursor(istring("i"), 60);
		assert(a, src);
		assert(a.type, src);
		assert(a.type.name == "int", src);
	}
}

unittest
{
	ModuleCache cache;

	writeln("Running the deduction from index expr tests...");
	{
		auto source = q{struct S{} S[] s; auto b = s[i];};
		auto pair = generateAutocompleteTrees(source, cache);
		DSymbol* S = pair.symbol.getFirstPartNamed(internString("S"));
		DSymbol* b = pair.symbol.getFirstPartNamed(internString("b"));
		assert(S);
		assert(b.type is S);
	}
	{
		auto source = q{struct S{} S[1] s; auto b = s[i];};
		auto pair = generateAutocompleteTrees(source, cache);
		DSymbol* S = pair.symbol.getFirstPartNamed(internString("S"));
		DSymbol* b = pair.symbol.getFirstPartNamed(internString("b"));
		assert(S);
		assert(b.type is S);
	}
	{
		auto source = q{struct S{} S[][] s; auto b = s[0];};
		auto pair = generateAutocompleteTrees(source, cache);
		DSymbol* S = pair.symbol.getFirstPartNamed(internString("S"));
		DSymbol* b = pair.symbol.getFirstPartNamed(internString("b"));
		assert(S);
		assert(b.type.type is S);
	}
	{
		auto source = q{struct S{} S[][][] s; auto b = s[0][0];};
		auto pair = generateAutocompleteTrees(source, cache);
		DSymbol* S = pair.symbol.getFirstPartNamed(internString("S"));
		DSymbol* b = pair.symbol.getFirstPartNamed(internString("b"));
		assert(S);
		assert(b.type.name == ARRAY_SYMBOL_NAME);
		assert(b.type.type is S);
	}
	{
		auto source = q{struct S{} S s; auto b = [s][0];};
		auto pair = generateAutocompleteTrees(source, cache);
		DSymbol* S = pair.symbol.getFirstPartNamed(internString("S"));
		DSymbol* b = pair.symbol.getFirstPartNamed(internString("b"));
		assert(S);
		assert(b.type is S);
	}
}

unittest
{
	ModuleCache cache;

	writeln("Running `super` tests...");
	auto source = q{ class A {} class B : A {} };
	auto pair = generateAutocompleteTrees(source, cache);
	assert(pair.symbol);
	auto A = pair.symbol.getFirstPartNamed(internString("A"));
	auto B = pair.symbol.getFirstPartNamed(internString("B"));
	auto scopeA = (pair.scope_.getScopeByCursor(A.location + A.name.length));
	auto scopeB = (pair.scope_.getScopeByCursor(B.location + B.name.length));
	assert(scopeA !is scopeB);

	assert(!scopeA.getSymbolsByName(SUPER_SYMBOL_NAME).length);
	assert(scopeB.getSymbolsByName(SUPER_SYMBOL_NAME)[0].type is A);
}

unittest
{
	ModuleCache cache;

	writeln("Running the \"access chain with inherited type\" tests...");
	auto source = q{ class A {} class B : A {} };
	auto pair = generateAutocompleteTrees(source, cache);
	assert(pair.symbol);
	auto A = pair.symbol.getFirstPartNamed(internString("A"));
	assert(A);
	auto B = pair.symbol.getFirstPartNamed(internString("B"));
	assert(B);
	auto AfromB = B.getFirstPartNamed(internString("A"));
	assert(AfromB.kind == CompletionKind.aliasName);
	assert(AfromB.type is A);
}

unittest
{
	ModuleCache cache;

	writeln("Running template type parameters tests...");
	{
		auto source = q{ struct Foo(T : int){} struct Bar(T : Foo){} };
		auto pair = generateAutocompleteTrees(source, "", 0, cache);
		DSymbol* T1 = pair.symbol.getFirstPartNamed(internString("Foo"));
		DSymbol* T2 = T1.getFirstPartNamed(internString("T"));
		assert(T2.type.name == "int");
		DSymbol* T3 = pair.symbol.getFirstPartNamed(internString("Bar"));
		DSymbol* T4 = T3.getFirstPartNamed(internString("T"));
		assert(T4.type);
		assert(T4.type == T1);
	}
	{
		auto source = q{ struct Foo(T){ }};
		auto pair = generateAutocompleteTrees(source, "", 0, cache);
		DSymbol* T1 = pair.symbol.getFirstPartNamed(internString("Foo"));
		assert(T1);
		DSymbol* T2 = T1.getFirstPartNamed(internString("T"));
		assert(T2);
		assert(T2.kind == CompletionKind.typeTmpParam);
	}
}

unittest
{
	ModuleCache cache;

	writeln("Running template variadic parameters tests...");
	auto source = q{ struct Foo(T...){ }};
	auto pair = generateAutocompleteTrees(source, "", 0, cache);
	DSymbol* T1 = pair.symbol.getFirstPartNamed(internString("Foo"));
	assert(T1);
	DSymbol* T2 = T1.getFirstPartNamed(internString("T"));
	assert(T2);
	assert(T2.kind == CompletionKind.variadicTmpParam);
}

unittest
{
	writeln("Running public import tests...");

	const dir = buildPath(tempDir(), "dsymbol");
	const fnameA = buildPath(dir, "a.d");
	const fnameB = buildPath(dir, "b.d");
	const fnameC = buildPath(dir, "c.d");
	const fnameD = buildPath(dir, "d.d");
	const srcA = q{ int x; int w; };
	const srcB = q{ float y; private float z; };
	const srcC = q{ public { import a : x; import b; } import a : w; long t; };
	const srcD = q{ public import c; };
	// A simpler diagram:
	// a = x w
	// b = y [z]
	// c = t + (x y) [w]
	// d = (t x y)

	mkdir(dir);
	write(fnameA, srcA);
	write(fnameB, srcB);
	write(fnameC, srcC);
	write(fnameD, srcD);
	scope (exit)
	{
		remove(fnameA);
		remove(fnameB);
		remove(fnameC);
		remove(fnameD);
		rmdir(dir);
	}

	ModuleCache cache;
	cache.addImportPaths([dir]);

	const a = cache.getModuleSymbol(istring(fnameA));
	const b = cache.getModuleSymbol(istring(fnameB));
	const c = cache.getModuleSymbol(istring(fnameC));
	const d = cache.getModuleSymbol(istring(fnameD));
	const ax = a.getFirstPartNamed(istring("x"));
	const aw = a.getFirstPartNamed(istring("w"));
	assert(ax);
	assert(aw);
	assert(ax.type && ax.type.name == "int");
	assert(aw.type && aw.type.name == "int");
	const by = b.getFirstPartNamed(istring("y"));
	const bz = b.getFirstPartNamed(istring("z"));
	assert(by);
	assert(bz);
	assert(by.type && by.type.name == "float");
	assert(bz.type && bz.type.name == "float");
	const ct = c.getFirstPartNamed(istring("t"));
	const cw = c.getFirstPartNamed(istring("w"));
	const cx = c.getFirstPartNamed(istring("x"));
	const cy = c.getFirstPartNamed(istring("y"));
	const cz = c.getFirstPartNamed(istring("z"));
	assert(ct);
	assert(ct.type && ct.type.name == "long");
	assert(cw is null); // skipOver is true
	assert(cx is ax);
	assert(cy is by);
	assert(cz is bz); // should not be there, but it is handled by DCD
	const dt = d.getFirstPartNamed(istring("t"));
	const dw = d.getFirstPartNamed(istring("w"));
	const dx = d.getFirstPartNamed(istring("x"));
	const dy = d.getFirstPartNamed(istring("y"));
	const dz = d.getFirstPartNamed(istring("z"));
	assert(dt is ct);
	assert(dw is null);
	assert(dx is cx);
	assert(dy is cy);
	assert(dz is cz);
}

unittest
{
	ModuleCache cache;

	writeln("Testing protection scopes");
	auto source = q{version(all) { private: } struct Foo{ }};
	auto pair = generateAutocompleteTrees(source, "", 0, cache);
	DSymbol* T1 = pair.symbol.getFirstPartNamed(internString("Foo"));
	assert(T1);
	assert(T1.protection != tok!"private");
}

// check for memory leaks on thread termination (in static constructors)
version (linux)
unittest
{
	import core.memory : GC;
	import core.thread : Thread;
	import fs = std.file;
	import std.array : split;
	import std.conv : to;

	// get the resident set size
	static long getRSS()
	{
		GC.collect();
		GC.minimize();
		// read Linux process statistics
		const txt = fs.readText("/proc/self/stat");
		const parts = split(txt);
		return to!long(parts[23]);
	}

	const rssBefore = getRSS();
	// create and destroy a lot of dummy threads
	foreach (j; 0 .. 50)
	{
		Thread[100] arr;
		foreach (i; 0 .. 100)
			arr[i] = new Thread({}).start();
		foreach (i; 0 .. 100)
			arr[i].join();
	}
	const rssAfter = getRSS();
	// check the process memory increase with some eyeballed threshold
	assert(rssAfter - rssBefore < 5000);
}

// this is for testing that internString data is always on the same address
// since we use this special property for modulecache recursion guard
unittest
{
	istring a = internString("foo_bar_baz".idup);
	istring b = internString("foo_bar_baz".idup);
	assert(a.data.ptr == b.data.ptr);
}

private StringCache stringCache = void;
static this()
{
	stringCache = StringCache(StringCache.defaultBucketCount);
}
static ~this()
{
	destroy(stringCache);
}

const(Token)[] lex(string source)
{
	return lex(source, null);
}

const(Token)[] lex(string source, string filename)
{
	import dparse.lexer : getTokensForParser;
	import std.string : representation;
	LexerConfig config;
	config.fileName = filename;
	return getTokensForParser(source.dup.representation, config, &stringCache);
}

unittest
{
	auto tokens = lex(q{int a = 9;});
	foreach(i, t;
		cast(IdType[]) [tok!"int", tok!"identifier", tok!"=", tok!"intLiteral", tok!";"])
	{
		assert(tokens[i] == t);
	}
	assert(tokens[1].text == "a", tokens[1].text);
	assert(tokens[3].text == "9", tokens[3].text);
}

string randomDFilename()
{
	import std.uuid : randomUUID;
	return "dsymbol_" ~ randomUUID().toString() ~ ".d";
}

ScopeSymbolPair generateAutocompleteTrees(string source, ref ModuleCache cache)
{
	return generateAutocompleteTrees(source, randomDFilename, cache);
}

ScopeSymbolPair generateAutocompleteTrees(string source, string filename, ref ModuleCache cache)
{
	auto tokens = lex(source);
	RollbackAllocator rba;
	Module m = parseModule(tokens, filename, &rba);

	scope first = new FirstPass(m, internString(filename), &cache);
	first.run();

	secondPass(first.rootSymbol, first.moduleScope, cache);
	auto r = first.rootSymbol.acSymbol;
	typeid(SemanticSymbol).destroy(first.rootSymbol);
	return ScopeSymbolPair(r, first.moduleScope);
}

ScopeSymbolPair generateAutocompleteTrees(string source, size_t cursorPosition, ref ModuleCache cache)
{
	return generateAutocompleteTrees(source, null, cache);
}

ScopeSymbolPair generateAutocompleteTrees(string source, string filename, size_t cursorPosition, ref ModuleCache cache)
{
	auto tokens = lex(source);
	RollbackAllocator rba;
	return dsymbol.conversion.generateAutocompleteTrees(
		tokens, &rba, cursorPosition, cache);
}
