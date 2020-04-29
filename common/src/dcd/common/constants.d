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
	ConstantCompletion("BigEndian"),
	ConstantCompletion("BSD"),
	ConstantCompletion("Core"),
	ConstantCompletion("CRuntime_Bionic"),
	ConstantCompletion("CRuntime_DigitalMars"),
	ConstantCompletion("CRuntime_Glibc"),
	ConstantCompletion("CRuntime_Microsoft"),
	ConstantCompletion("CRuntime_Musl"),
	ConstantCompletion("CRuntime_UClibc"),
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
	ConstantCompletion("WatchOS"),
	ConstantCompletion("WebAssembly"),
	ConstantCompletion("Win32"),
	ConstantCompletion("Win64"),
	ConstantCompletion("Windows"),
	ConstantCompletion("X86"),
	ConstantCompletion("X86_64")
];
