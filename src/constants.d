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
	"getAliasThis",
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
 * Compiler-defined values for version() conditions.
 */
immutable string[] predefinedVersions = [
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
	"D_Warnings",
	"D_SoftFloat",
	"D_Version2",
	"D_X32",
	"FreeBSD",
	"FreeStanding",
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
	"X86_64",
];
