module dsymbol.builtin.names;

import dparse.lexer;
import dsymbol.string_interning;

package istring[24] builtinTypeNames;

// Constants for buit-in or dummy symbol names

/**
 * Type suffix, in breadcrumbs this appends ["callTip string", FUNCTION_SYMBOL_NAME]
 *
 * To check a DSymbol type for this name, instead check `qualifier == SymbolQualifier.func`
 *
 * This gets appended for `T delegate(Args)` types, with T as child type. The
 * parameters are not currently resolved or exposed.
 */
@("function") istring FUNCTION_SYMBOL_NAME;
/**
 * Type suffix, in breadcrumbs this is a single entry.
 *
 * To check a DSymbol type for this name, instead check `qualifier == SymbolQualifier.array`
 *
 * This will appear as type name for `T[]` items, with T as child type.
 *
 * Index accessing an array DSymbol will either return itself for slices/ranges,
 * or the child type for single index access.
 */
@("*arr*") istring ARRAY_SYMBOL_NAME;
/**
 * Type suffix, in breadcrumbs this is a single entry.
 *
 * To check a DSymbol type for this name, instead check `qualifier == SymbolQualifier.assocArray`
 *
 * This will appear as type name for `V[K]` items, with V as child type. K is
 * not currently resolved or exposed.
 *
 * Index accessing an AA DSymbol will always return the child type.
 */
@("*aa*") istring ASSOC_ARRAY_SYMBOL_NAME;
/**
 * Type suffix, in breadcrumbs this is a single entry.
 *
 * To check a DSymbol type for this name, instead check `qualifier == SymbolQualifier.pointer`
 *
 * This will appear as type name for `T*` items, with T as child type.
 *
 * Pointer DSymbol types have special parts resolving mechanics, as they
 * implicitly dereference single-layer pointers. Otherwise they also behave like
 * arrays with index accessing.
 */
@("*") istring POINTER_SYMBOL_NAME;

/** 
 * Allocated as semantic symbol & DSymbol with this name + generates a new scope.
 * Inserted for function literals. (e.g. delegates like `(foo) { ... }`)
 *
 * Only inserted for function literals with block statement and function body.
 *
 * Name of the function type is FUNCTION_LITERAL_SYMBOL_NAME, also being
 * embedded inside the calltip.
 */
@("*function-literal*") istring FUNCTION_LITERAL_SYMBOL_NAME;
/** 
 * Generated from imports, where each full module/package import is a single
 * semantic symbol & DSymbol. DSymbol's `skipOver` is set to true if it's not a
 * public import. For each identifier inside the import identifier chain a
 * DSymbol with the name set to the identifier is generated. The CompletionKind
 * is `CompletionKind.packageName` for each of them, except for the final (last)
 * identifier, which has `CompletionKind.moduleName`. Only the first identifier
 * is added as child to the scope, then each identifier is added as child to the
 * last one. Existing symbols are reused, so a full tree structure is built here.
 *
 * Import binds (`import importChain : a, b = c`) generate a semantic symbol for
 * each bind, with the name being IMPORT_SYMBOL_NAME for symbols that are not
 * renamed (`a` in this example) or the rename for symbols that are renamed (`b`
 * in this example). Binds are resolved in the second pass via breadcrumbs. For
 * the two binds in this example the breadcrumbs are `["a"]` and `["c", "b"]`
 * respectively.
 *
 * An implicit `import object;` is generated and inserted as first child of each
 * module, assuming `object` could be resolved.
 *
 * Additionally this symbol name is generated as DSymbol with
 * CompletionKind.importSymbol in second pass for type inheritance, to import
 * all children of the base type. Classes also get an additional
 * $(LREF SUPER_SYMBOL_NAME) child as CompletionKind.variableName.
 *
 * `alias x this;` generates an IMPORT_SYMBOL_NAME DSymbol with
 * CompletionKind.importSymbol, as well as adding itself to `aliasThisSymbols`
 *
 * `mixin Foo;` for Foo mixin templates generates an IMPORT_SYMBOL_NAME DSymbol
 * with CompletionKind.importSymbol as child.
 */
@("import") istring IMPORT_SYMBOL_NAME;
/** 
 * Breadcrumb type that is emitted for array literals and array initializers.
 *
 * Gets built into an array DSymbol with the element type as child type and
 * qualifier == SymbolQualifier.array. This has the same semantics as
 * $(LREF ARRAY_SYMBOL_NAME) afterwards.
 *
 * Breadcrumb structure <first item initializer breadcrumbs> ~ [ARRAY_LITERAL_SYMBOL_NAME]
 *
 * Empty arrays insert `VOID_SYMBOL_NAME` in place of the first item initializer
 * breadcrumbs.
 */
@("*arr-literal*") istring ARRAY_LITERAL_SYMBOL_NAME;
/// unused currently, use-case unclear, might get removed or repurposed.
@("*parameters*") istring PARAMETERS_SYMBOL_NAME;
/// works pretty much like IMPORT_SYMBOL_NAME, but without renamed symbols. Can
/// probably be merged into one.
///
/// Emitted for `with(x) { ... }` with WITH_SYMBOL_NAME as DSymbol and getting
/// the value parsed as initializer.
@("with") istring WITH_SYMBOL_NAME;
/**
 * Generated SemanticSymbol and DSymbol with this name for constructors.
 * Otherwise behaves like functions, with CompletionKind.functionName, with no
 * child type. The SemanticSymbol parent is the aggregate type. For the calltip,
 * $(LREF THIS_SYMBOL_NAME) is used as name.
 *
 * Automatically generated for structs and unions if no explicit one is provided
 * (with custom generated calltip).
 *
 * Symbols with this name are never returned as import child.
 *
 * Symbols with this name are excluded from auto-completion (only appear in calltips)
 */
@("*constructor*") istring CONSTRUCTOR_SYMBOL_NAME;
/**
 * Generated SemanticSymbol and DSymbol with this name for destructors.
 * Otherwise behaves like functions, with CompletionKind.functionName, with no
 * child type and no parameters. The calltip is hardcoded `~this()`
 *
 * Only emitted when explicitly written in code, not auto-generated.
 *
 * Symbols with this name are never returned as import child.
 */
@("~this") istring DESTRUCTOR_SYMBOL_NAME;
/**
 * Generated SemanticSymbol and DSymbol with this name for unittests.
 * Otherwise behaves like functions, with CompletionKind.dummy, with no
 * child type, no parameters and no symbol file.
 *
 * Due to being CompletionKind.dummy, this should never appear in any output.
 *
 * Symbols with this name are never returned as import child.
 */
@("*unittest*") istring UNITTEST_SYMBOL_NAME;
/**
 * Implicitly generated DSymbol for `this`. Child of structs, with type being
 * set to the struct type.
 *
 * Symbols with this name are never returned as import child.
 */
@("this") istring THIS_SYMBOL_NAME;
/// Currently unused, might get removed and implemented differently.
@("_argptr") istring ARGPTR_SYMBOL_NAME;
/// Currently unused, might get removed and implemented differently.
@("_arguments") istring ARGUMENTS_SYMBOL_NAME;
/**
 * This symbol name is generated as DSymbol with CompletionKind.variableName in
 * second pass for classes with inheritance, to import all children of the base
 * class. DSymbol child of the class type, with the baseClass as its child type.
 */
@("super") istring SUPER_SYMBOL_NAME;

/**
 * Breadcrumb part in initializer type generation for literal values in the
 * source code.
 *
 * These match the built-in type names, but with prefixed `*` to indicate that
 * they are values.
 *
 * $(LREF symbolNameToTypeName) converts the literal breadcrumb to a built-in
 * type name, which is looked up in the module scope and used as initializer
 * type. (first entry only)
 */
@("*double") istring DOUBLE_LITERAL_SYMBOL_NAME;
/// ditto
@("*float") istring FLOAT_LITERAL_SYMBOL_NAME;
/// ditto
@("*idouble") istring IDOUBLE_LITERAL_SYMBOL_NAME;
/// ditto
@("*ifloat") istring IFLOAT_LITERAL_SYMBOL_NAME;
/// ditto
@("*int") istring INT_LITERAL_SYMBOL_NAME;
/// ditto
@("*long") istring LONG_LITERAL_SYMBOL_NAME;
/// ditto
@("*real") istring REAL_LITERAL_SYMBOL_NAME;
/// ditto
@("*ireal") istring IREAL_LITERAL_SYMBOL_NAME;
/// ditto
@("*uint") istring UINT_LITERAL_SYMBOL_NAME;
/// ditto
@("*ulong") istring ULONG_LITERAL_SYMBOL_NAME;
/// ditto
@("*char") istring CHAR_LITERAL_SYMBOL_NAME;
/// ditto
@("*dstring") istring DSTRING_LITERAL_SYMBOL_NAME;
/// ditto
@("*string") istring STRING_LITERAL_SYMBOL_NAME;
/// ditto
@("*wstring") istring WSTRING_LITERAL_SYMBOL_NAME;
/// ditto
@("*bool") istring BOOL_VALUE_SYMBOL_NAME;
/// ditto
@("*void") istring VOID_SYMBOL_NAME;

/**
 * Translates the IDs for built-in types into an interned string.
 */
istring getBuiltinTypeName(IdType id) nothrow @nogc @safe
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

	static foreach (member; __traits(allMembers, dsymbol.builtin.names))
	{
		static if (member.length > 11 && member[$ - 11 .. $] == "SYMBOL_NAME"
			&& is(typeof(__traits(getMember, dsymbol.builtin.names, member)) == istring))
		{
			__traits(getMember, dsymbol.builtin.names, member) = internString(
				__traits(getAttributes, __traits(getMember, dsymbol.builtin.names, member))[0]
			);
		}
	}
}

istring symbolNameToTypeName(istring name)
{
	if (name == DOUBLE_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[2];
	if (name == FLOAT_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[4];
	if (name == IDOUBLE_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[3];
	if (name == IFLOAT_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[5];
	if (name == INT_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[0];
	if (name == LONG_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[8];
	if (name == REAL_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[17];
	if (name == IREAL_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[18];
	if (name == UINT_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[1];
	if (name == ULONG_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[9];
	if (name == CHAR_LITERAL_SYMBOL_NAME)
		return builtinTypeNames[10];
	if (name == DSTRING_LITERAL_SYMBOL_NAME)
		return istring("dstring");
	if (name == STRING_LITERAL_SYMBOL_NAME)
		return istring("string");
	if (name == WSTRING_LITERAL_SYMBOL_NAME)
		return istring("wstring");
	if (name == BOOL_VALUE_SYMBOL_NAME)
		return builtinTypeNames[13];
	if (name == VOID_SYMBOL_NAME)
		return builtinTypeNames[14];
	return name;
}
