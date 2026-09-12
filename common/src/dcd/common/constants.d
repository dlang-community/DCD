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

public import dcd.common.constants2;

// The lists in this module should be kept sorted.

struct ConstantCompletion
{
	string identifier;
	string ddoc;
}

/**
 * Linkage types
 */
immutable ConstantCompletion[] linkages = [
	// https://dlang.org/spec/attribute.html#linkage
	// custom typed instead of copied from the docs to fit completions better
	ConstantCompletion("C", "Enforces C calling conventions for the function, no mangling."),
	ConstantCompletion("C++", "Offers limited compatibility with C++."),
	ConstantCompletion("D", "Default D mangling and calling conventions."),
	ConstantCompletion("Objective-C", "Objective-C offers limited compatibility with Objective-C, see the "
		~ "$(LINK2 objc_interface.html, Interfacing to Objective-C) documentation for more information."),
	ConstantCompletion("Pascal"),
	ConstantCompletion("System", "`Windows` on Windows platforms, `C` on other platforms."),
	ConstantCompletion("Windows", "Enforces Win32/`__stdcall` conventions for the function.")
];

/**
 * Scope conditions
 */
immutable ConstantCompletion[] scopes = [
	ConstantCompletion("exit", "Executes statements when the scope exits normally or due to exception unwinding."),
	ConstantCompletion("failure", "Executes statements when the scope exits due to exception unwinding."),
	ConstantCompletion("success", "Executes statements when the scope exits normally.")
];
/**
 * Function attributes that can appear AFTER a function's parameter list,
 * e.g. `void foo() pure @safe { ... }`.
 * https://dlang.org/spec/attribute.html
 */
immutable ConstantCompletion[] functionAttributes = [
	ConstantCompletion("nothrow", "The function cannot throw exceptions."),
	ConstantCompletion("pure", "The function cannot access any mutable global or static state."),
	ConstantCompletion("return", "Marks return scope / return ref parameters."),
	ConstantCompletion("scope", "The function does not escape references to its scope parameters."),
];

/**
 * Function attributes that can appear AFTER a METHOD's parameter list
 * only (a function declared inside a struct/class/interface), e.g.
 * `void foo() const { ... }` - a free function cannot be `const`.
 * https://dlang.org/spec/attribute.html
 */
immutable ConstantCompletion[] methodAttributes = [
	ConstantCompletion("const", "The method cannot modify mutable state reachable through `this`."),
	ConstantCompletion("immutable", "The method can only access immutable data."),
	ConstantCompletion("inout", "The method preserves the mutability of its inout parameters."),
	ConstantCompletion("shared", "The method can access shared data."),
];

/**
 * Attributes and storage classes that can START a declaration
 * (`pure void f()`, `static int x`, `auto y = 1`). Offered at declaration
 * boundaries: after `;`, `{`, `}`, at the beginning of a file, or after
 * another attribute.
 * https://dlang.org/spec/attribute.html
 */
immutable ConstantCompletion[] declarationAttributes = [
	ConstantCompletion("abstract", "Class cannot be instantiated directly, or method must be overridden."),
	ConstantCompletion("auto", "Type is inferred from the initializer or return statement."),
	ConstantCompletion("const", "Data that cannot be modified."),
	ConstantCompletion("final", "Method cannot be overridden by derived classes, or class has no subclasses."),
	ConstantCompletion("immutable", "Data that cannot be modified, directly or via references."),
	ConstantCompletion("inout", "Applies the inout storage class to a parameter or a function."),
	ConstantCompletion("nothrow", "Function cannot throw exceptions."),
	ConstantCompletion("override", "Function overrides a base class method."),
	ConstantCompletion("pure", "Function cannot access any mutable global or static state."),
	ConstantCompletion("ref", "Function returns a reference, or parameter is passed by reference."),
	ConstantCompletion("return", "Marks a return scope parameter or a return ref."),
	ConstantCompletion("scope", "Restricts the lifetime of a parameter or a delegate."),
	ConstantCompletion("shared", "Data that is shared between threads."),
	ConstantCompletion("static", "Storage class: one instance per thread or per type."),
	ConstantCompletion("synchronized", "Only one thread at a time can execute the function."),
	ConstantCompletion("__gshared", "Data that is shared between threads, bypassing the type system."),
];

/**
 * Attributes that are spelled with a leading `@` in a declaration attribute
 * position. https://dlang.org/spec/attribute.html#uda
 */
immutable ConstantCompletion[] atAttributes = [
	ConstantCompletion("@disable", "Prevents the compiler from generating a default member (e.g. `@disable this();`)."),
	ConstantCompletion("@live", "Enables better guarantees for pointers to live memory."),
	ConstantCompletion("@nogc", "Function cannot allocate memory with the garbage collector."),
	ConstantCompletion("@property", "Function is called with property syntax, without parentheses."),
	ConstantCompletion("@safe", "Function is checked for memory safety."),
	ConstantCompletion("@system", "Function is not checked for memory safety (the default)."),
	ConstantCompletion("@trusted", "Function is assumed to be memory safe by the programmer."),
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
	ConstantCompletion("AsmJS"),
	ConstantCompletion("assert"),
	ConstantCompletion("AVR"),
	ConstantCompletion("BigEndian"),
	ConstantCompletion("BSD"),
	ConstantCompletion("Core"),
	ConstantCompletion("CRuntime_Bionic"),
	ConstantCompletion("CRuntime_DigitalMars"),
	ConstantCompletion("CRuntime_Glibc"),
	ConstantCompletion("CRuntime_Microsoft"),
	ConstantCompletion("CRuntime_Musl"),
	ConstantCompletion("CRuntime_UClibc"),
	ConstantCompletion("CRuntime_WASI"),
	ConstantCompletion("CppRuntime_Clang"),
	ConstantCompletion("CppRuntime_DigitalMars"),
	ConstantCompletion("CppRuntime_Gcc"),
	ConstantCompletion("CppRuntime_Microsoft"),
	ConstantCompletion("CppRuntime_Sun"),
	ConstantCompletion("Cygwin"),
	ConstantCompletion("DigitalMars"),
	ConstantCompletion("DragonFlyBSD"),
	ConstantCompletion("D_AVX"),
	ConstantCompletion("D_AVX2"),
	ConstantCompletion("D_BetterC"),
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
	ConstantCompletion("MSP430"),
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
	ConstantCompletion("Std"),
	ConstantCompletion("SystemZ"),
	ConstantCompletion("SysV3"),
	ConstantCompletion("SysV4"),
	ConstantCompletion("TVOS"),
	ConstantCompletion("unittest"),
	ConstantCompletion("WASI"),
	ConstantCompletion("WatchOS"),
	ConstantCompletion("WebAssembly"),
	ConstantCompletion("Win32"),
	ConstantCompletion("Win64"),
	ConstantCompletion("Windows"),
	ConstantCompletion("X86"),
	ConstantCompletion("X86_64")
];
