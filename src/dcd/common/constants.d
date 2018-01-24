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

private static immutable pragmaDDoc = import("pragma.dd");
private static immutable traitsDDoc = import("traits.dd");

template fetchDocDDforDT(string ddoc, string dtStart)
{
	enum fetchDocDDforDT = {
		import std.string : lineSplitter, KeepTerminator, stripLeft, stripRight,
			strip, startsWith, endsWith;

		bool found;
		string ret;
		string indent;
		bool inCode;
		foreach (line; ddoc.lineSplitter!(KeepTerminator.yes))
		{
			if (line.stripLeft.startsWith("$(DT $(LNAME2 ", "$(SPEC_SUBNAV_PREV_NEXT"))
			{
				if (found) // abort on new section if in section
					break;
				else if (line.stripLeft.startsWith("$(DT $(LNAME2 " ~ dtStart)) // set section if correct
				{
					indent = line[0 .. $ - line.stripLeft.length];
					found = true;
				}
			}
			else if (found)
			{
				if (line.startsWith("---")) // code blocks aren't indented
					inCode = !inCode;

				if (inCode)
					ret ~= line;
				else
				{
					if (line.startsWith(indent)) // strip indentation of DT
						ret ~= line[indent.length .. $];
					else
						ret ~= line;
				}
			}
		}
		if (!found)
			throw new Exception("DT '" ~ dtStart ~ "' was not found");
		// ret still has `$(DD content)` around it, strip that
		if (ret.startsWith("$(DD"))
		{
			ret = ret[4 .. $].strip;
			if (ret.endsWith(")"))
				ret = ret[0 .. $ - 1].stripRight;
		}
		return ret;
	}();
}

template fetchDocByGNAME(string ddoc, string gname)
{
	enum fetchDocByGNAME = {
		import std.algorithm : canFind;
		import std.string : lineSplitter, KeepTerminator, strip, stripLeft,
			startsWith;

		bool found;
		bool inCode;
		string ret;
		string indent;
		foreach (line; ddoc.lineSplitter!(KeepTerminator.yes))
		{
			if (line.canFind("$(GNAME ", "$(LNAME2") || line.stripLeft.startsWith("$(SPEC_SUBNAV_PREV_NEXT"))
			{
				if (found)
					break;
				else if (line.canFind("$(GNAME " ~ gname ~ ")"))
					found = true;
			}
			else if (found)
			{
				if (line.startsWith("---"))
					inCode = !inCode;
				if (inCode)
					ret ~= line;
				else
				{
					if (!ret.length)
						indent = line[0 .. $ - line.stripLeft.length];
					if (line.startsWith(indent))
						ret ~= line[indent.length .. $];
					else
						ret ~= line;
				}
			}
		}
		if (!found)
			throw new Exception("GNAME '" ~ gname ~ "' was not found");
		return ret.strip;
	}();
}

template pragmaConstantCompletion(string field)
{
	enum ConstantCompletion pragmaConstantCompletion = ConstantCompletion(field, fetchDocDDforDT!(pragmaDDoc, field));
}

template traitsConstantCompletion(string field)
{
	enum ConstantCompletion traitsConstantCompletion = ConstantCompletion(field, fetchDocByGNAME!(traitsDDoc, field));
}

/**
 * Pragma arguments
 */
immutable ConstantCompletion[] pragmas = [
	// docs from https://github.com/dlang/dlang.org/blob/master/spec/pragma.dd
	pragmaConstantCompletion!"inline",
	pragmaConstantCompletion!"lib",
	pragmaConstantCompletion!"mangle",
	pragmaConstantCompletion!"msg",
	pragmaConstantCompletion!"startaddress"
];

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
 * Traits arguments
 */
immutable ConstantCompletion[] traits = [
	// https://github.com/dlang/dlang.org/blob/master/spec/traits.dd
	traitsConstantCompletion!"allMembers",
	traitsConstantCompletion!"classInstanceSize",
	traitsConstantCompletion!"compiles",
	traitsConstantCompletion!"derivedMembers",
	traitsConstantCompletion!"getAliasThis",
	traitsConstantCompletion!"getAttributes",
	traitsConstantCompletion!"getFunctionAttributes",
	traitsConstantCompletion!"getFunctionVariadicStyle",
	traitsConstantCompletion!"getLinkage",
	traitsConstantCompletion!"getMember",
	traitsConstantCompletion!"getOverloads",
	traitsConstantCompletion!"getParameterStorageClasses",
	traitsConstantCompletion!"getPointerBitmap",
	traitsConstantCompletion!"getProtection",
	traitsConstantCompletion!"getUnitTests",
	traitsConstantCompletion!"getVirtualFunctions",
	traitsConstantCompletion!"getVirtualIndex",
	traitsConstantCompletion!"getVirtualMethods",
	traitsConstantCompletion!"hasMember",
	traitsConstantCompletion!"identifier",
	traitsConstantCompletion!"isAbstractClass",
	traitsConstantCompletion!"isAbstractFunction",
	traitsConstantCompletion!"isArithmetic",
	traitsConstantCompletion!"isAssociativeArray",
	traitsConstantCompletion!"isDeprecated",
	traitsConstantCompletion!"isDisabled",
	traitsConstantCompletion!"isFinalClass",
	traitsConstantCompletion!"isFinalFunction",
	traitsConstantCompletion!"isFloating",
	traitsConstantCompletion!"isFuture",
	traitsConstantCompletion!"isIntegral",
	traitsConstantCompletion!"isLazy",
	traitsConstantCompletion!"isNested",
	traitsConstantCompletion!"isOut",
	traitsConstantCompletion!"isOverrideFunction",
	traitsConstantCompletion!"isPOD",
	traitsConstantCompletion!"isRef",
	traitsConstantCompletion!"isSame",
	traitsConstantCompletion!"isScalar",
	traitsConstantCompletion!"isStaticArray",
	traitsConstantCompletion!"isStaticFunction",
	traitsConstantCompletion!"isTemplate",
	traitsConstantCompletion!"isUnsigned",
	traitsConstantCompletion!"isVirtualFunction",
	traitsConstantCompletion!"isVirtualMethod",
	traitsConstantCompletion!"parent"
];

pragma(msg, traits);

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
