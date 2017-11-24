/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2014 Brian Schott
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module dcd.common.constants;

// The lists in this module should be kept sorted.

struct ConstantCompletion
{
	string identifier;
	string ddoc;
}

/**
 * Pragma arguments
 */
immutable ConstantCompletion[] pragmas = [
	// docs from https://github.com/dlang/dlang.org/blob/master/spec/pragma.dd
	ConstantCompletion("inline", `$(P Affects whether functions are inlined or not. If at the declaration level, it
affects the functions declared in the block it controls. If inside a function, it
affects the function it is enclosed by. If there are multiple pragma inlines in a function,
the lexically last one takes effect.)

$(P It takes three forms:)
$(OL
	$(LI
---
pragma(inline)
---
	Sets the behavior to match the default behavior set by the compiler switch
	$(DDSUBLINK dmd, switch-inline, $(TT -inline)).
	)
	$(LI
---
pragma(inline, false)
---
	Functions are never inlined.
	)
	$(LI
---
pragma(inline, true)
---
	If a function cannot be inlined with the $(DDSUBLINK dmd, switch-inline, $(TT -inline))
	switch, an error message is issued. This is expected to be improved in the future to causing
	functions to always be inlined regardless of compiler switch settings. Whether a compiler can
	inline a particular function or not is implementation defined.
	)
)
---
pragma(inline):
int foo(int x) // foo() is never inlined
{
	pragma(inline, true);
	++x;
	pragma(inline, false); // supercedes the others
	return x + 3;
}
---`),
	ConstantCompletion("lib", `Inserts a directive in the object file to link in the library
specified by the $(ASSIGNEXPRESSION).
The $(ASSIGNEXPRESSION)s must be a string literal:
-----------------
pragma(lib, "foo.lib");
-----------------`),
	ConstantCompletion("mangle", `Overrides the default mangling for a symbol. It's only effective
when the symbol is a function declaration or a variable declaration.
For example this allows linking to a symbol which is a D keyword, which would normally
be disallowed as a symbol name:
-----------------
pragma(mangle, "body")
extern(C) void body_func();
-----------------`),
	ConstantCompletion("msg", `Constructs a message from the arguments and prints to the standard error stream while compiling:
-----------------
pragma(msg, "compiling...", 1, 1.0);
-----------------`),
	ConstantCompletion("startaddress", `Puts a directive into the object file saying that the
function specified in the first argument will be the
start address for the program:
-----------------
void foo() { ... }
pragma(startaddress, foo);
-----------------
This is not normally used for application level programming,
but is for specialized systems work.
For applications code, the start address is taken care of
by the runtime library.`)
];

/**
 * Linkage types
 */
immutable ConstantCompletion[] linkages = [
	// https://dlang.org/spec/attribute.html#linkage
	ConstantCompletion("C", "Enforces C calling conventions for the function, no mangling"),
	ConstantCompletion("C++", "offers limited compatibility with C++"),
	ConstantCompletion("D", "Default D mangling and calling conventions"),
	ConstantCompletion("Objective-C",
		"Objective-C offers limited compatibility with Objective-C, see the Interfacing to Objective-C documentation for more information"),
	ConstantCompletion("Pascal"),
	ConstantCompletion("System", "`Windows` on Windows platforms, `C` on other platforms."),
	ConstantCompletion("Windows", "Enforces Win32/`__stdcall` conventions for the function")
];

private immutable string isLazyDoc = `$(P Takes one argument. If that argument is a declaration,
	$(D true) is returned if it is $(D_KEYWORD ref), $(D_KEYWORD out),
	or $(D_KEYWORD lazy), otherwise $(D false).
)

---
void fooref(ref int x)
{
	static assert(__traits(isRef, x));
	static assert(!__traits(isOut, x));
	static assert(!__traits(isLazy, x));
}

void fooout(out int x)
{
	static assert(!__traits(isRef, x));
	static assert(__traits(isOut, x));
	static assert(!__traits(isLazy, x));
}

void foolazy(lazy int x)
{
	static assert(!__traits(isRef, x));
	static assert(!__traits(isOut, x));
	static assert(__traits(isLazy, x));
}
---`;

/**
 * Traits arguments
 */
immutable ConstantCompletion[] traits = [
	// https://github.com/dlang/dlang.org/blob/master/spec/traits.dd
	ConstantCompletion("allMembers", `Takes a single argument, which must evaluate to either
a type or an expression of type.
A tuple of string literals is returned, each of which
is the name of a member of that type combined with all
of the members of the base classes (if the type is a class).
No name is repeated.
Builtin properties are not included.`),
	ConstantCompletion("classInstanceSize", `Takes a single argument, which must evaluate to either
a class type or an expression of class type.
The result
is of type $(CODE size_t), and the value is the number of
bytes in the runtime instance of the class type.
It is based on the static type of a class, not the
polymorphic type.`),
	ConstantCompletion("compiles", `$(P Returns a bool $(D true) if all of the arguments
compile (are semantically correct).
The arguments can be symbols, types, or expressions that
are syntactically correct.
The arguments cannot be statements or declarations.
)

$(P If there are no arguments, the result is $(D false).)

---
import std.stdio;

struct S
{
	static int s1;
	int s2;
}

int foo();
int bar();

void main()
{
	writeln(__traits(compiles));                      // false
	writeln(__traits(compiles, foo));                 // true
	writeln(__traits(compiles, foo + 1));             // true
	writeln(__traits(compiles, &foo + 1));            // false
	writeln(__traits(compiles, typeof(1)));           // true
	writeln(__traits(compiles, S.s1));                // true
	writeln(__traits(compiles, S.s3));                // false
	writeln(__traits(compiles, 1,2,3,int,long,std));  // true
	writeln(__traits(compiles, 3[1]));                // false
	writeln(__traits(compiles, 1,2,3,int,long,3[1])); // false
}
---

$(P This is useful for:)

$(UL
$(LI Giving better error messages inside generic code than
the sometimes hard to follow compiler ones.)
$(LI Doing a finer grained specialization than template
partial specialization allows for.)
)`),
	ConstantCompletion("derivedMembers", `$(P Takes a single argument, which must evaluate to either
a type or an expression of type.
A tuple of string literals is returned, each of which
is the name of a member of that type.
No name is repeated.
Base class member names are not included.
Builtin properties are not included.
)

---
import std.stdio;

class D
{
	this() { }
	~this() { }
	void foo() { }
	int foo(int) { return 0; }
}

void main()
{
	auto a = [__traits(derivedMembers, D)];
	writeln(a);    // ["__ctor", "__dtor", "foo"]
}
---

$(P The order in which the strings appear in the result
is not defined.)`),
	ConstantCompletion("getAliasThis", `Takes one argument, a symbol of aggregate type.
If the given aggregate type has $(D alias this), returns a list of
$(D alias this) names, by a tuple of $(D string)s.
Otherwise returns an empty tuple.`),
	ConstantCompletion("getAttributes", `$(P
Takes one argument, a symbol. Returns a tuple of all attached user defined attributes.
If no UDA's exist it will return an empty tuple.
)

$(P
	For more information, see: $(DDSUBLINK spec/attribute, uda, User Defined Attributes)
)

---
@(3) int a;
@("string", 7) int b;

enum Foo;
@Foo int c;

pragma(msg, __traits(getAttributes, a));
pragma(msg, __traits(getAttributes, b));
pragma(msg, __traits(getAttributes, c));
---

Prints:

$(CONSOLE
tuple(3)
tuple("string", 7)
tuple((Foo))
)`),
	ConstantCompletion("getFunctionAttributes", `$(P
	Takes one argument which must either be a function symbol, function literal,
	or a function pointer. It returns a string tuple of all the attributes of
	that function $(B excluding) any user defined attributes (UDAs can be
	retrieved with the $(RELATIVE_LINK2 get-attributes, getAttributes) trait).
	If no attributes exist it will return an empty tuple.
)

$(B Note:) The order of the attributes in the returned tuple is
implementation-defined and should not be relied upon.

$(P
	A list of currently supported attributes are:)
	$(UL $(LI $(D pure), $(D nothrow), $(D @nogc), $(D @property), $(D @system), $(D @trusted), $(D @safe), and $(D ref)))
	$(B Note:) $(D ref) is a function attribute even though it applies to the return type.

$(P
	Additionally the following attributes are only valid for non-static member functions:)
	$(UL $(LI $(D const), $(D immutable), $(D inout), $(D shared)))

For example:

---
int sum(int x, int y) pure nothrow { return x + y; }

// prints ("pure", "nothrow", "@system")
pragma(msg, __traits(getFunctionAttributes, sum));

struct S
{
void test() const @system { }
}

// prints ("const", "@system")
pragma(msg, __traits(getFunctionAttributes, S.test));
---

$(P Note that some attributes can be inferred. For example:)

---
// prints ("pure", "nothrow", "@nogc", "@trusted")
pragma(msg, __traits(getFunctionAttributes, (int x) @trusted { return x * 2; }));
---`),
	ConstantCompletion("getFunctionVariadicStyle", `$(P
Takes one argument which must either be a function symbol, or a type
that is a function, delegate or a function pointer.
It returns a string identifying the kind of
$(LINK2 function.html#variadic, variadic arguments) that are supported.
)

$(TABLE2 getFunctionVariadicStyle,
$(THEAD string returned, kind, access, example)
$(TROW $(D "none"), not a variadic function, &nbsp;, $(D void foo();))
$(TROW $(D "argptr"), D style variadic function, $(D _argptr) and $(D _arguments), $(D void bar(...)))
$(TROW $(D "stdarg"), C style variadic function, $(LINK2 $(ROOT_DIR)phobos/core_stdc_stdarg.html, $(D core.stdc.stdarg)), $(D extern (C) void abc(int, ...)))
$(TROW $(D "typesafe"), typesafe variadic function, array on stack, $(D void def(int[] ...)))
)

---
import core.stdc.stdarg;

void novar() {}
extern(C) void cstyle(int, ...) {}
extern(C++) void cppstyle(int, ...) {}
void dstyle(...) {}
void typesafe(int[]...) {}

static assert(__traits(getFunctionVariadicStyle, novar) == "none");
static assert(__traits(getFunctionVariadicStyle, cstyle) == "stdarg");
static assert(__traits(getFunctionVariadicStyle, cppstyle) == "stdarg");
static assert(__traits(getFunctionVariadicStyle, dstyle) == "argptr");
static assert(__traits(getFunctionVariadicStyle, typesafe) == "typesafe");

static assert(__traits(getFunctionVariadicStyle, (int[] a...) {}) == "typesafe");
static assert(__traits(getFunctionVariadicStyle, typeof(cstyle)) == "stdarg");
---`),
	ConstantCompletion("getLinkage", `$(P Takes one argument, which is a declaration symbol, or the type of a function,
delegate, or pointer to function.
Returns a string representing the $(LINK2 attribute.html#LinkageAttribute, LinkageAttribute)
of the declaration.
The string is one of:
)

$(UL
$(LI $(D "D"))
$(LI $(D "C"))
$(LI $(D "C++"))
$(LI $(D "Windows"))
$(LI $(D "Pascal"))
$(LI $(D "Objective-C"))
$(LI $(D "System"))
)

---
extern (C) int fooc();
alias aliasc = fooc;

static assert(__traits(getLinkage, fooc) == "C");
static assert(__traits(getLinkage, aliasc) == "C");
---`),
	ConstantCompletion("getMember", `$(P Takes two arguments, the second must be a string.
The result is an expression formed from the first
argument, followed by a $(SINGLEQUOTE .), followed by the second
argument as an identifier.
)

---
import std.stdio;

struct S
{
	int mx;
	static int my;
}

void main()
{
	S s;

	__traits(getMember, s, "mx") = 1;  // same as s.mx=1;
	writeln(__traits(getMember, s, "m" ~ "x")); // 1

	__traits(getMember, S, "mx") = 1;  // error, no this for S.mx
	__traits(getMember, S, "my") = 2;  // ok
}
---`),
	ConstantCompletion("getOverloads", `$(P The first argument is an aggregate (e.g. struct/class/module).
The second argument is a string that matches the name of
one of the functions in that aggregate.
The result is a tuple of all the overloads of that function.
)

---
import std.stdio;

class D
{
	this() { }
	~this() { }
	void foo() { }
	int foo(int) { return 2; }
}

void main()
{
	D d = new D();

	foreach (t; __traits(getOverloads, D, "foo"))
		writeln(typeid(typeof(t)));

	alias b = typeof(__traits(getOverloads, D, "foo"));
	foreach (t; b)
		writeln(typeid(t));

	auto i = __traits(getOverloads, d, "foo")[1](1);
	writeln(i);
}
---

Prints:

$(CONSOLE
void()
int()
void()
int()
2
)`),
	ConstantCompletion("getParameterStorageClasses", `$(P
	Takes two arguments.
	The first must either be a function symbol, or a type
	that is a function, delegate or a function pointer.
	The second is an integer identifying which parameter, where the first parameter is
	0.
	It returns a tuple of strings representing the storage classes of that parameter.
)

---
ref int foo(return ref const int* p, scope int* a, out int b, lazy int c);

static assert(__traits(getParameterStorageClasses, foo, 0)[0] == "return");
static assert(__traits(getParameterStorageClasses, foo, 0)[1] == "ref");

static assert(__traits(getParameterStorageClasses, foo, 1)[0] == "scope");
static assert(__traits(getParameterStorageClasses, foo, 2)[0] == "out");
static assert(__traits(getParameterStorageClasses, typeof(&foo), 3)[0] == "lazy");
---`),
	ConstantCompletion("getPointerBitmap", `$(P The argument is a type.
	The result is an array of $(D size_t) describing the memory used by an instance of the given type.
)
$(P The first element of the array is the size of the type (for classes it is
	the $(GBLINK classInstanceSize)).)
$(P The following elements describe the locations of GC managed pointers within the
	memory occupied by an instance of the type.
	For type T, there are $(D T.sizeof / size_t.sizeof) possible pointers represented
	by the bits of the array values.)
$(P This array can be used by a precise GC to avoid false pointers.)
---
class C
{
	// implicit virtual function table pointer not marked
	// implicit monitor field not marked, usually managed manually
	C next;
	size_t sz;
	void* p;
	void function () fn; // not a GC managed pointer
}

struct S
{
	size_t val1;
	void* p;
	C c;
	byte[] arr;          // { length, ptr }
	void delegate () dg; // { context, func }
}

static assert (__traits(getPointerBitmap, C) == [6*size_t.sizeof, 0b010100]);
static assert (__traits(getPointerBitmap, S) == [7*size_t.sizeof, 0b0110110]);
---`),
	ConstantCompletion("getProtection", `$(P The argument is a symbol.
	The result is a string giving its protection level: "public", "private", "protected", "export", or "package".
)

---
import std.stdio;

class D
{
	export void foo() { }
	public int bar;
}

void main()
{
	D d = new D();

	auto i = __traits(getProtection, d.foo);
	writeln(i);

	auto j = __traits(getProtection, d.bar);
	writeln(j);
}
---

Prints:

$(CONSOLE
export
public
)`),
	ConstantCompletion("getUnitTests", `$(P
	Takes one argument, a symbol of an aggregate (e.g. struct/class/module).
	The result is a tuple of all the unit test functions of that aggregate.
	The functions returned are like normal nested static functions,
	$(DDSUBLINK glossary, ctfe, CTFE) will work and
	$(DDSUBLINK spec/attribute, uda, UDA's) will be accessible.
)

$(H3 Note:)

$(P
	The -unittest flag needs to be passed to the compiler. If the flag
	is not passed $(CODE __traits(getUnitTests)) will always return an
	empty tuple.
)

---
module foo;

import core.runtime;
import std.stdio;

struct name { string name; }

class Foo
{
	unittest
	{
		writeln("foo.Foo.unittest");
	}
}

@name("foo") unittest
{
	writeln("foo.unittest");
}

template Tuple (T...)
{
	alias Tuple = T;
}

shared static this()
{
	// Override the default unit test runner to do nothing. After that, "main" will
	// be called.
	Runtime.moduleUnitTester = { return true; };
}

void main()
{
	writeln("start main");

	alias tests = Tuple!(__traits(getUnitTests, foo));
	static assert(tests.length == 1);

	alias attributes = Tuple!(__traits(getAttributes, tests[0]));
	static assert(attributes.length == 1);

	foreach (test; tests)
		test();

	foreach (test; __traits(getUnitTests, Foo))
		test();
}
---

$(P By default, the above will print:)

$(CONSOLE
start main
foo.unittest
foo.Foo.unittest
)`),
	ConstantCompletion("getVirtualFunctions", `The same as $(GLINK getVirtualMethods), except that
final functions that do not override anything are included.`),
	ConstantCompletion("getVirtualIndex", `Takes a single argument which must evaluate to a function.
The result is a $(CODE ptrdiff_t) containing the index
of that function within the vtable of the parent type.
If the function passed in is final and does not override
a virtual function, $(D -1) is returned instead.`),
	ConstantCompletion("getVirtualMethods", `$(P The first argument is a class type or an expression of
	class type.
	The second argument is a string that matches the name of
	one of the functions of that class.
	The result is a tuple of the virtual overloads of that function.
	It does not include final functions that do not override anything.
)

---
import std.stdio;

class D
{
	this() { }
	~this() { }
	void foo() { }
	int foo(int) { return 2; }
}

void main()
{
	D d = new D();

	foreach (t; __traits(getVirtualMethods, D, "foo"))
		writeln(typeid(typeof(t)));

	alias b = typeof(__traits(getVirtualMethods, D, "foo"));
	foreach (t; b)
		writeln(typeid(t));

	auto i = __traits(getVirtualMethods, d, "foo")[1](1);
	writeln(i);
}
---

Prints:

$(CONSOLE
void()
int()
void()
int()
2
)`),
	ConstantCompletion("hasMember", `$(P The first argument is a type that has members, or
	is an expression of a type that has members.
	The second argument is a string.
	If the string is a valid property of the type,
	$(D true) is returned, otherwise $(D false).
)

---
import std.stdio;

struct S
{
	int m;
}

void main()
{
	S s;

	writeln(__traits(hasMember, S, "m")); // true
	writeln(__traits(hasMember, s, "m")); // true
	writeln(__traits(hasMember, S, "y")); // false
	writeln(__traits(hasMember, int, "sizeof")); // true
}
---`),
	ConstantCompletion("identifier", `$(P Takes one argument, a symbol. Returns the identifier
	for that symbol as a string literal.
)
---
import std.stdio;

int var = 123;
pragma(msg, typeof(var));                       // int
pragma(msg, typeof(__traits(identifier, var))); // string
writeln(var);                                   // 123
writeln(__traits(identifier, var));             // "var"
---`),
	ConstantCompletion("isAbstractClass", `$(P If the arguments are all either types that are abstract classes,
	or expressions that are typed as abstract classes, then $(D true)
	is returned.
	Otherwise, $(D false) is returned.
	If there are no arguments, $(D false) is returned.)

---
import std.stdio;

abstract class C { int foo(); }

void main()
{
	C c;
	writeln(__traits(isAbstractClass, C));
	writeln(__traits(isAbstractClass, c, C));
	writeln(__traits(isAbstractClass));
	writeln(__traits(isAbstractClass, int*));
}
---

Prints:

$(CONSOLE
true
true
false
false
)`),
	ConstantCompletion("isAbstractFunction", `$(P Takes one argument. If that argument is an abstract function,
	$(D true) is returned, otherwise $(D false).
)

---
import std.stdio;

struct S
{
	void bar() { }
}

class C
{
	void bar() { }
}

class AC
{
	abstract void foo();
}

void main()
{
	writeln(__traits(isAbstractFunction, C.bar));   // false
	writeln(__traits(isAbstractFunction, S.bar));   // false
	writeln(__traits(isAbstractFunction, AC.foo));  // true
}
---`),
	ConstantCompletion("isArithmetic", `$(P If the arguments are all either types that are arithmetic types,
	or expressions that are typed as arithmetic types, then $(D true)
	is returned.
	Otherwise, $(D false) is returned.
	If there are no arguments, $(D false) is returned.)

---
import std.stdio;

void main()
{
	int i;
	writeln(__traits(isArithmetic, int));
	writeln(__traits(isArithmetic, i, i+1, int));
	writeln(__traits(isArithmetic));
	writeln(__traits(isArithmetic, int*));
}
---

Prints:

$(CONSOLE
true
true
false
false
)`),
	ConstantCompletion("isAssociativeArray", `Works like $(D isArithmetic), except it's for associative array types.`),
	ConstantCompletion("isFinalClass", `Works like $(D isAbstractClass), except it's for final classes.`),
	ConstantCompletion("isFinalFunction", `$(P Takes one argument. If that argument is a final function,
	$(D true) is returned, otherwise $(D false).
)

---
import std.stdio;

struct S
{
	void bar() { }
}

class C
{
	void bar() { }
	final void foo();
}

final class FC
{
	void foo();
}

void main()
{
	writeln(__traits(isFinalFunction, C.bar));  // false
	writeln(__traits(isFinalFunction, S.bar));  // false
	writeln(__traits(isFinalFunction, C.foo));  // true
	writeln(__traits(isFinalFunction, FC.foo)); // true
}
---`),
	ConstantCompletion("isFloating", `Works like $(D isArithmetic), except it's for floating
point types (including imaginary and complex types).`),
	ConstantCompletion("isFuture", "Takes one argument. It returns `true` if the argument is a symbol
marked with the `@future` keyword, otherwise `false`. Currently, only
functions and variable declarations have support for the `@future` keyword."),
	ConstantCompletion("isIntegral", `Works like $(D isArithmetic), except it's for integral
types (including character types).`),
	ConstantCompletion("isLazy", isLazyDoc),
	ConstantCompletion("isNested", `Takes one argument.
It returns $(D true) if the argument is a nested type which internally
stores a context pointer, otherwise it returns $(D false).
Nested types can be  $(DDSUBLINK spec/class, nested, classes),
$(DDSUBLINK spec/struct, nested, structs), and
$(DDSUBLINK spec/function, variadicnested, functions).`),
	ConstantCompletion("isOut", isLazyDoc),
	ConstantCompletion("isOverrideFunction", `$(P Takes one argument. If that argument is a function marked with
	$(D_KEYWORD override), $(D true) is returned, otherwise $(D false).
)

---
import std.stdio;

class Base
{
	void foo() { }
}

class Foo : Base
{
	override void foo() { }
	void bar() { }
}

void main()
{
	writeln(__traits(isOverrideFunction, Base.foo)); // false
	writeln(__traits(isOverrideFunction, Foo.foo));  // true
	writeln(__traits(isOverrideFunction, Foo.bar));  // false
}
---`),
	ConstantCompletion("isPOD", `$(P Takes one argument, which must be a type. It returns
$(D true) if the type is a $(DDSUBLINK glossary, pod, POD) type, otherwise $(D false).)`),
	ConstantCompletion("isRef", isLazyDoc),
	ConstantCompletion("isSame", `$(P Takes two arguments and returns bool $(D true) if they
	are the same symbol, $(D false) if not.)

---
import std.stdio;

struct S { }

int foo();
int bar();

void main()
{
	writeln(__traits(isSame, foo, foo)); // true
	writeln(__traits(isSame, foo, bar)); // false
	writeln(__traits(isSame, foo, S));   // false
	writeln(__traits(isSame, S, S));     // true
	writeln(__traits(isSame, std, S));   // false
	writeln(__traits(isSame, std, std)); // true
}
---

$(P If the two arguments are expressions made up of literals
or enums that evaluate to the same value, true is returned.)`),
	ConstantCompletion("isScalar", `Works like $(D isArithmetic), except it's for scalar types.`),
	ConstantCompletion("isStaticArray", `Works like $(D isArithmetic), except it's for static array types.`),
	ConstantCompletion("isStaticFunction", `Takes one argument. If that argument is a static function,
meaning it has no context pointer,
$(D true) is returned, otherwise $(D false).`),
	ConstantCompletion("isTemplate", `$(P Takes one argument. If that argument is a template then $(D true) is returned,
	otherwise $(D false).
)

---
void foo(T)(){}
static assert(__traits(isTemplate,foo));
static assert(!__traits(isTemplate,foo!int()));
static assert(!__traits(isTemplate,"string"));
---`),
	ConstantCompletion("isUnsigned", `Works like $(D isArithmetic), except it's for unsigned types.`),
	ConstantCompletion("isVirtualFunction", `The same as $(GLINK isVirtualMethod), except
that final functions that don't override anything return true.`),
	ConstantCompletion("isVirtualMethod", `Takes one argument. If that argument is a virtual function,
$(D true) is returned, otherwise $(D false).
Final functions that don't override anything return false.`),
	ConstantCompletion("parent", `Takes a single argument which must evaluate to a symbol.
The result is the symbol that is the parent of it.`)
];

/**
 * Scope conditions
 */
immutable ConstantCompletion[] scopes = [
	ConstantCompletion("exit", "executes statements when the scope exits normally or due to exception unwinding"),
	ConstantCompletion("failure", "executes statements when the scope exits due to exception unwinding"),
	ConstantCompletion("success", "executes statements when the scope exits normally")
];

/**
 * Compiler-defined values for version() conditions.
 */
immutable ConstantCompletion[] predefinedVersions = [
	ConstantCompletion("AArch64"),
	ConstantCompletion("AIX"),
	ConstantCompletion("all"),
	ConstantCompletion("Alpha"),
	ConstantCompletion("Alpha_HardFloat"),
	ConstantCompletion("Alpha_SoftFloat"),
	ConstantCompletion("Android"),
	ConstantCompletion("ARM"),
	ConstantCompletion("ARM_HardFloat"),
	ConstantCompletion("ARM_SoftFloat"),
	ConstantCompletion("ARM_SoftFP"),
	ConstantCompletion("ARM_Thumb"),
	ConstantCompletion("assert"),
	ConstantCompletion("BigEndian"),
	ConstantCompletion("BSD"),
	ConstantCompletion("CRuntime_Bionic"),
	ConstantCompletion("CRuntime_DigitalMars"),
	ConstantCompletion("CRuntime_Glibc"),
	ConstantCompletion("CRuntime_Microsoft"),
	ConstantCompletion("Cygwin"),
	ConstantCompletion("DigitalMars"),
	ConstantCompletion("DragonFlyBSD"),
	ConstantCompletion("D_Coverage"),
	ConstantCompletion("D_Ddoc"),
	ConstantCompletion("D_HardFloat"),
	ConstantCompletion("D_InlineAsm_X86"),
	ConstantCompletion("D_InlineAsm_X86_64"),
	ConstantCompletion("D_LP64"),
	ConstantCompletion("D_NoBoundsChecks"),
	ConstantCompletion("D_PIC"),
	ConstantCompletion("D_SIMD"),
	ConstantCompletion("D_SoftFloat"),
	ConstantCompletion("D_Version2"),
	ConstantCompletion("D_X32"),
	ConstantCompletion("ELFv1"),
	ConstantCompletion("ELFv2"),
	ConstantCompletion("Epiphany"),
	ConstantCompletion("FreeBSD"),
	ConstantCompletion("FreeStanding"),
	ConstantCompletion("GNU"),
	ConstantCompletion("Haiku"),
	ConstantCompletion("HPPA"),
	ConstantCompletion("HPPA64"),
	ConstantCompletion("Hurd"),
	ConstantCompletion("IA64"),
	ConstantCompletion("iOS"),
	ConstantCompletion("LDC"),
	ConstantCompletion("linux"),
	ConstantCompletion("LittleEndian"),
	ConstantCompletion("MinGW"),
	ConstantCompletion("MIPS32"),
	ConstantCompletion("MIPS64"),
	ConstantCompletion("MIPS_EABI"),
	ConstantCompletion("MIPS_HardFloat"),
	ConstantCompletion("MIPS_N32"),
	ConstantCompletion("MIPS_N64"),
	ConstantCompletion("MIPS_O32"),
	ConstantCompletion("MIPS_O64"),
	ConstantCompletion("MIPS_SoftFloat"),
	ConstantCompletion("NetBSD"),
	ConstantCompletion("none"),
	ConstantCompletion("NVPTX"),
	ConstantCompletion("NVPTX64"),
	ConstantCompletion("OpenBSD"),
	ConstantCompletion("OSX"),
	ConstantCompletion("PlayStation"),
	ConstantCompletion("PlayStation4"),
	ConstantCompletion("Posix"),
	ConstantCompletion("PPC"),
	ConstantCompletion("PPC64"),
	ConstantCompletion("PPC_HardFloat"),
	ConstantCompletion("PPC_SoftFloat"),
	ConstantCompletion("RISCV32"),
	ConstantCompletion("RISCV64"),
	ConstantCompletion("S390"),
	ConstantCompletion("S390X"),
	ConstantCompletion("SDC"),
	ConstantCompletion("SH"),
	ConstantCompletion("SH64"),
	ConstantCompletion("SkyOS"),
	ConstantCompletion("Solaris"),
	ConstantCompletion("SPARC"),
	ConstantCompletion("SPARC64"),
	ConstantCompletion("SPARC_HardFloat"),
	ConstantCompletion("SPARC_SoftFloat"),
	ConstantCompletion("SPARC_V8Plus"),
	ConstantCompletion("SystemZ"),
	ConstantCompletion("SysV3"),
	ConstantCompletion("SysV4"),
	ConstantCompletion("TVOS"),
	ConstantCompletion("unittest"),
	ConstantCompletion("WatchOS"),
	ConstantCompletion("Win32"),
	ConstantCompletion("Win64"),
	ConstantCompletion("Windows"),
	ConstantCompletion("X86"),
	ConstantCompletion("X86_64")
];
