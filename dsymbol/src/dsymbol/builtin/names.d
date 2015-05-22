module dsymbol.builtin.names;

import std.d.lexer;
import dsymbol.string_interning;

package immutable(istring[24]) builtinTypeNames;

/// Constants for buit-in or dummy symbol names
immutable istring IMPORT_SYMBOL_NAME;
/// ditto
immutable istring WITH_SYMBOL_NAME;
/// ditto
immutable istring CONSTRUCTOR_SYMBOL_NAME;
/// ditto
immutable istring DESTRUCTOR_SYMBOL_NAME;
/// ditto
immutable istring ARGPTR_SYMBOL_NAME;
/// ditto
immutable istring ARGUMENTS_SYMBOL_NAME;
/// ditto
immutable istring THIS_SYMBOL_NAME;
/// ditto
immutable istring SUPER_SYMBOL_NAME;
/// ditto
immutable istring UNITTEST_SYMBOL_NAME;
/// ditto
immutable istring DOUBLE_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring FLOAT_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring IDOUBLE_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring IFLOAT_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring INT_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring LONG_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring REAL_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring IREAL_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring UINT_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring ULONG_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring CHAR_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring DSTRING_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring STRING_LITERAL_SYMBOL_NAME;
/// ditto
immutable istring WSTRING_LITERAL_SYMBOL_NAME;

/**
 * Translates the IDs for built-in types into an interned string.
 */
istring getBuiltinTypeName(IdType id) nothrow pure @nogc @safe
{
	switch (id)
	{
	case tok!"int": return builtinTypeNames[0];
	case tok!"uint": return builtinTypeNames[1];
	case tok!"double": return builtinTypeNames[2];
	case tok!"idouble": return builtinTypeNames[3];
	case tok!"float": return builtinTypeNames[4];
	case tok!"ifloat": return builtinTypeNames[5];
	case tok!"short": return builtinTypeNames[6];
	case tok!"ushort": return builtinTypeNames[7];
	case tok!"long": return builtinTypeNames[8];
	case tok!"ulong": return builtinTypeNames[9];
	case tok!"char": return builtinTypeNames[10];
	case tok!"wchar": return builtinTypeNames[11];
	case tok!"dchar": return builtinTypeNames[12];
	case tok!"bool": return builtinTypeNames[13];
	case tok!"void": return builtinTypeNames[14];
	case tok!"cent": return builtinTypeNames[15];
	case tok!"ucent": return builtinTypeNames[16];
	case tok!"real": return builtinTypeNames[17];
	case tok!"ireal": return builtinTypeNames[18];
	case tok!"byte": return builtinTypeNames[19];
	case tok!"ubyte": return builtinTypeNames[20];
	case tok!"cdouble": return builtinTypeNames[21];
	case tok!"cfloat": return builtinTypeNames[22];
	case tok!"creal": return builtinTypeNames[23];
	default: assert (false);
	}
}


/**
 * Initializes builtin types and the various properties of builtin types
 */
static this()
{
	builtinTypeNames[0] = internString("int");
	builtinTypeNames[1] = internString("uint");
	builtinTypeNames[2] = internString("double");
	builtinTypeNames[3] = internString("idouble");
	builtinTypeNames[4] = internString("float");
	builtinTypeNames[5] = internString("ifloat");
	builtinTypeNames[6] = internString("short");
	builtinTypeNames[7] = internString("ushort");
	builtinTypeNames[8] = internString("long");
	builtinTypeNames[9] = internString("ulong");
	builtinTypeNames[10] = internString("char");
	builtinTypeNames[11] = internString("wchar");
	builtinTypeNames[12] = internString("dchar");
	builtinTypeNames[13] = internString("bool");
	builtinTypeNames[14] = internString("void");
	builtinTypeNames[15] = internString("cent");
	builtinTypeNames[16] = internString("ucent");
	builtinTypeNames[17] = internString("real");
	builtinTypeNames[18] = internString("ireal");
	builtinTypeNames[19] = internString("byte");
	builtinTypeNames[20] = internString("ubyte");
	builtinTypeNames[21] = internString("cdouble");
	builtinTypeNames[22] = internString("cfloat");
	builtinTypeNames[23] = internString("creal");

	IMPORT_SYMBOL_NAME = internString("public");
	WITH_SYMBOL_NAME = internString("with");
	CONSTRUCTOR_SYMBOL_NAME = internString("*constructor*");
	DESTRUCTOR_SYMBOL_NAME = internString("~this");
	ARGPTR_SYMBOL_NAME = internString("_argptr");
	ARGUMENTS_SYMBOL_NAME = internString("_arguments");
	THIS_SYMBOL_NAME = internString("this");
	SUPER_SYMBOL_NAME = internString("super");
	UNITTEST_SYMBOL_NAME = internString("*unittest*");
	DOUBLE_LITERAL_SYMBOL_NAME = internString("*double");
	FLOAT_LITERAL_SYMBOL_NAME = internString("*float");
	IDOUBLE_LITERAL_SYMBOL_NAME = internString("*idouble");
	IFLOAT_LITERAL_SYMBOL_NAME = internString("*ifloat");
	INT_LITERAL_SYMBOL_NAME = internString("*int");
	LONG_LITERAL_SYMBOL_NAME = internString("*long");
	REAL_LITERAL_SYMBOL_NAME = internString("*real");
	IREAL_LITERAL_SYMBOL_NAME = internString("*ireal");
	UINT_LITERAL_SYMBOL_NAME = internString("*uint");
	ULONG_LITERAL_SYMBOL_NAME = internString("*ulong");
	CHAR_LITERAL_SYMBOL_NAME = internString("*char");
	DSTRING_LITERAL_SYMBOL_NAME = internString("*dstring");
	STRING_LITERAL_SYMBOL_NAME = internString("*string");
	WSTRING_LITERAL_SYMBOL_NAME = internString("*wstring");
}
