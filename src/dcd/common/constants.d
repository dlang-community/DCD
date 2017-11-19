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

/**
 * Pragma arguments
 */
immutable string[] pragmas = [
	"inline",
	"lib",
	"mangle",
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
	"Objective-C",
	"Pascal",
	"System",
	"Windows"
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
	"getFunctionAttributes",
	"getFunctionVariadicStyle",
	"getLinkage",
	"getMember",
	"getOverloads",
	"getParameterStorageClasses",
	"getPointerBitmap",
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
	"isTemplate",
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
	"CRuntime_Bionic",
	"CRuntime_DigitalMars",
	"CRuntime_Glibc",
	"CRuntime_Microsoft",
	"Cygwin",
	"DigitalMars",
	"DragonFlyBSD",
	"D_Coverage",
	"D_Ddoc",
	"D_HardFloat",
	"D_InlineAsm_X86",
	"D_InlineAsm_X86_64",
	"D_LP64",
	"D_NoBoundsChecks",
	"D_PIC",
	"D_SIMD",
	"D_SoftFloat",
	"D_Version2",
	"D_X32",
	"ELFv1",
	"ELFv2",
	"Epiphany",
	"FreeBSD",
	"FreeStanding",
	"GNU",
	"Haiku",
	"HPPA",
	"HPPA64",
	"Hurd",
	"IA64",
	"iOS",
	"LDC",
	"linux",
	"LittleEndian",
	"MinGW",
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
	"NVPTX",
	"NVPTX64",
	"OpenBSD",
	"OSX",
	"PlayStation",
	"PlayStation4",
	"Posix",
	"PPC",
	"PPC64",
	"PPC_HardFloat",
	"PPC_SoftFloat",
	"RISCV32",
	"RISCV64",
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
	"SystemZ",
	"SysV3",
	"SysV4",
	"TVOS",
	"unittest",
	"WatchOS",
	"Win32",
	"Win64",
	"Windows",
	"X86",
	"X86_64"
];
