/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2013 Brian Schott
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

module constants;

// The lists in this module should be kept sorted.

/**
 * Pragma arguments
 */
immutable string[] pragmas = [
	"lib",
	"msg",
	"startaddress"
];

/**
 * Linkage types
 */
immutable string[] linkages = [
	"C",
	"C++",
	"D",
	"Pascal",
	"System",
	"Windows",
];

/**
 * Traits arguments
 */
immutable string[] traits = [
	"allMembers",
	"classInstanceSize",
	"compiles",
	"derivedMembers",
	"getAttributes",
	"getMember",
	"getOverloads",
	"getProtection",
	"getUnitTests",
	"getVirtualFunctions",
	"getVirtualIndex",
	"getVirtualMethods",
	"hasMember",
	"identifier",
	"isAbstractClass",
	"isAbstractFunction",
	"isArithmetic",
	"isAssociativeArray",
	"isFinalClass",
	"isFinalFunction",
	"isFloating",
	"isIntegral",
	"isLazy",
	"isNested",
	"isOut",
	"isOverrideFunction",
	"isPOD",
	"isRef",
	"isSame",
	"isScalar",
	"isStaticArray",
	"isStaticFunction",
	"isUnsigned",
	"isVirtualFunction",
	"isVirtualMethod",
	"parent"
];

/**
 * Scope conditions
 */
immutable string[] scopes = [
	"exit",
	"failure",
	"success"
];

/**
 * Predefined version identifiers
 */
immutable string[] versions = [
	"AArch64",
	"AIX",
	"all",
	"Alpha",
	"Alpha_HardFloat",
	"Alpha_SoftFloat",
	"Android",
	"ARM",
	"ARM_HardFloat",
	"ARM_SoftFloat",
	"ARM_SoftFP",
	"ARM_Thumb",
	"assert",
	"BigEndian",
	"BSD",
	"Cygwin",
	"D_Coverage",
	"D_Ddoc",
	"D_HardFloat",
	"DigitalMars",
	"D_InlineAsm_X86",
	"D_InlineAsm_X86_64",
	"D_LP64",
	"D_NoBoundsChecks",
	"D_PIC",
	"DragonFlyBSD",
	"D_SIMD",
	"D_SoftFloat",
	"D_Version2",
	"D_X32",
	"FreeBSD",
	"GNU",
	"Haiku",
	"HPPA",
	"HPPA64",
	"Hurd",
	"IA64",
	"LDC",
	"linux",
	"LittleEndian",
	"MIPS32",
	"MIPS64",
	"MIPS_EABI",
	"MIPS_HardFloat",
	"MIPS_N32",
	"MIPS_N64",
	"MIPS_O32",
	"MIPS_O64",
	"MIPS_SoftFloat",
	"NetBSD",
	"none",
	"OpenBSD",
	"OSX",
	"Posix",
	"PPC",
	"PPC64",
	"PPC_HardFloat",
	"PPC_SoftFloat",
	"S390",
	"S390X",
	"SDC",
	"SH",
	"SH64",
	"SkyOS",
	"Solaris",
	"SPARC",
	"SPARC64",
	"SPARC_HardFloat",
	"SPARC_SoftFloat",
	"SPARC_V8Plus",
	"SysV3",
	"SysV4",
	"unittest",
	"Win32",
	"Win64",
	"Windows",
	"X86",
	"X86_64"
];

/**
 * Properties of class types
 */
immutable string[] classProperties = [
	"alignof",
	"classinfo",
	"init",
	"mangleof",
	"__monitor",
	"sizeof",
	"stringof",
	"tupleof",
	"__vptr",
];

/**
 * Properties of struct types
 */
immutable string[] structProperties = [
	"alignof",
	"tupleof",
	"init",
	"mangleof",
	"sizeof",
	"stringof"
];

immutable string[] predefinedVersions;

static this()
{
	version(AArch64) predefinedVersions ~= "AArch64";
	version(AIX) predefinedVersions ~= "AIX";
	version(all) predefinedVersions ~= "all";
	version(Alpha) predefinedVersions ~= "Alpha";
	version(Alpha_HardFloat) predefinedVersions ~= "Alpha_HardFloat";
	version(Alpha_SoftFloat) predefinedVersions ~= "Alpha_SoftFloat";
	version(Android) predefinedVersions ~= "Android";
	version(ARM) predefinedVersions ~= "ARM";
	version(ARM_HardFloat) predefinedVersions ~= "ARM_HardFloat";
	version(ARM_SoftFloat) predefinedVersions ~= "ARM_SoftFloat";
	version(ARM_SoftFP) predefinedVersions ~= "ARM_SoftFP";
	version(ARM_Thumb) predefinedVersions ~= "ARM_Thumb";
	version(assert) predefinedVersions ~= "assert";
	version(BigEndian) predefinedVersions ~= "BigEndian";
	version(BSD) predefinedVersions ~= "BSD";
	version(Cygwin) predefinedVersions ~= "Cygwin";
	version(D_Coverage) predefinedVersions ~= "D_Coverage";
	version(D_Ddoc) predefinedVersions ~= "D_Ddoc";
	version(D_HardFloat) predefinedVersions ~= "D_HardFloat";
	version(DigitalMars) predefinedVersions ~= "DigitalMars";
	version(D_InlineAsm_X86) predefinedVersions ~= "D_InlineAsm_X86";
	version(D_InlineAsm_X86_64) predefinedVersions ~= "D_InlineAsm_X86_64";
	version(D_LP64) predefinedVersions ~= "D_LP64";
	version(D_NoBoundsChecks) predefinedVersions ~= "D_NoBoundsChecks";
	version(D_PIC) predefinedVersions ~= "D_PIC";
	version(DragonFlyBSD) predefinedVersions ~= "DragonFlyBSD";
	version(D_SIMD) predefinedVersions ~= "D_SIMD";
	version(D_SoftFloat) predefinedVersions ~= "D_SoftFloat";
	version(D_Version2) predefinedVersions ~= "D_Version2";
	version(D_X32) predefinedVersions ~= "D_X32";
	version(FreeBSD) predefinedVersions ~= "FreeBSD";
	version(GNU) predefinedVersions ~= "GNU";
	version(Haiku) predefinedVersions ~= "Haiku";
	version(HPPA) predefinedVersions ~= "HPPA";
	version(HPPA64) predefinedVersions ~= "HPPA64";
	version(Hurd) predefinedVersions ~= "Hurd";
	version(IA64) predefinedVersions ~= "IA64";
	version(LDC) predefinedVersions ~= "LDC";
	version(linux) predefinedVersions ~= "linux";
	version(LittleEndian) predefinedVersions ~= "LittleEndian";
	version(MIPS32) predefinedVersions ~= "MIPS32";
	version(MIPS64) predefinedVersions ~= "MIPS64";
	version(MIPS_EABI) predefinedVersions ~= "MIPS_EABI";
	version(MIPS_HardFloat) predefinedVersions ~= "MIPS_HardFloat";
	version(MIPS_N32) predefinedVersions ~= "MIPS_N32";
	version(MIPS_N64) predefinedVersions ~= "MIPS_N64";
	version(MIPS_O32) predefinedVersions ~= "MIPS_O32";
	version(MIPS_O64) predefinedVersions ~= "MIPS_O64";
	version(MIPS_SoftFloat) predefinedVersions ~= "MIPS_SoftFloat";
	version(NetBSD) predefinedVersions ~= "NetBSD";
	version(none) predefinedVersions ~= "none";
	version(OpenBSD) predefinedVersions ~= "OpenBSD";
	version(OSX) predefinedVersions ~= "OSX";
	version(Posix) predefinedVersions ~= "Posix";
	version(PPC) predefinedVersions ~= "PPC";
	version(PPC64) predefinedVersions ~= "PPC64";
	version(PPC_HardFloat) predefinedVersions ~= "PPC_HardFloat";
	version(PPC_SoftFloat) predefinedVersions ~= "PPC_SoftFloat";
	version(S390) predefinedVersions ~= "S390";
	version(S390X) predefinedVersions ~= "S390X";
	version(SDC) predefinedVersions ~= "SDC";
	version(SH) predefinedVersions ~= "SH";
	version(SH64) predefinedVersions ~= "SH64";
	version(SkyOS) predefinedVersions ~= "SkyOS";
	version(Solaris) predefinedVersions ~= "Solaris";
	version(SPARC) predefinedVersions ~= "SPARC";
	version(SPARC64) predefinedVersions ~= "SPARC64";
	version(SPARC_HardFloat) predefinedVersions ~= "SPARC_HardFloat";
	version(SPARC_SoftFloat) predefinedVersions ~= "SPARC_SoftFloat";
	version(SPARC_V8Plus) predefinedVersions ~= "SPARC_V8Plus";
	version(SysV3) predefinedVersions ~= "SysV3";
	version(SysV4) predefinedVersions ~= "SysV4";
	version(unittest) predefinedVersions ~= "unittest";
	version(Win32) predefinedVersions ~= "Win32";
	version(Win64) predefinedVersions ~= "Win64";
	version(Windows) predefinedVersions ~= "Windows";
	version(X86) predefinedVersions ~= "X86";
	version(X86_64) predefinedVersions ~= "X86_64";
}
