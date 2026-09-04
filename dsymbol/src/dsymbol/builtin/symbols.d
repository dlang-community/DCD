module dsymbol.builtin.symbols;

/*
 * The documentation strings passed to makeSymbol() are condensed from the
 * D language specification at dlang.org:
 *   - .mangleof, .stringof, .init, .sizeof, .alignof, .min, .max and the
 *     floating point properties (.dig, .epsilon, .infinity, .mant_dig,
 *     .max_10_exp, .max_exp, .min_exp, .min_10_exp, .min_normal, .nan,
 *     .re, .im): spec/property.html
 *   - .length, .ptr, .dup, .idup: spec/arrays.html#array-properties
 *   - byKey, byValue, clear, get, keys, values, rehash: spec/hash-map.html#properties
 *   - .offsetof, .tupleof: spec/struct.html#struct_properties
 *   - .classinfo, __vptr, __monitor: spec/class.html#class_properties
 *   - enum .init, .min, .max: spec/enum.html#enum_properties
 */

import containers.hashset;
import containers.ttree;
import dparse.rollback_allocator;
import dsymbol.builtin.names;
import dsymbol.string_interning;
import dsymbol.symbol;
import std.experimental.allocator.mallocator : Mallocator;

private alias SymbolsAllocator = Mallocator;

/**
 * Symbols for the built in types
 */
TTree!(DSymbol*, SymbolsAllocator, true, "a < b") builtinSymbols;

/**
 * Array properties
 */
TTree!(DSymbol*, SymbolsAllocator, true, "a < b") arraySymbols;

/**
 * Associative array properties
 */
TTree!(DSymbol*, SymbolsAllocator, true, "a < b") assocArraySymbols;

/**
 * Struct, enum, union, class, and interface properties
 */
TTree!(DSymbol*, SymbolsAllocator, true, "a < b") aggregateSymbols;

/**
 * Class properties
 */
TTree!(DSymbol*, SymbolsAllocator, true, "a < b") classSymbols;

/**
 * Enum properties
 */
TTree!(DSymbol*, SymbolsAllocator, true, "a < b") enumSymbols;

/**
 * Pointer properties (when not implicitly dereferencing)
 */
TTree!(DSymbol*, SymbolsAllocator, true, "a < b") pointerSymbols;

/**
 * The built-in `.offsetof` property of struct/class/union fields.
 * Deliberately NOT inserted into any property tree: `offsetof` is only
 * valid on a field access expression (e.g. `s.field.offsetof`), never on
 * a type or a plain value, so it is appended to completion results only
 * when the expression before the dot resolves to a field symbol.
 */
DSymbol* offsetofSymbol;

/**
 * Properties for the template arguments of declarations (none)
 */
TTree!(DSymbol*, SymbolsAllocator, true, "a < b") templatedSymbols;
/**
 * Variadic template parameters properties
 */
DSymbol* variadicTmpParamSymbol;

/**
 * Type template parameters properties (when no colon constraint)
 */
DSymbol* typeTmpParamSymbol;

static this()
{
	auto bool_ = makeSymbol(builtinTypeNames[13], CompletionKind.keyword);
	auto int_ = makeSymbol(builtinTypeNames[0], CompletionKind.keyword);
	auto long_ = makeSymbol(builtinTypeNames[8], CompletionKind.keyword);
	auto byte_ = makeSymbol(builtinTypeNames[19], CompletionKind.keyword);
	auto char_ = makeSymbol(builtinTypeNames[10], CompletionKind.keyword);
	auto dchar_ = makeSymbol(builtinTypeNames[12], CompletionKind.keyword);
	auto short_ = makeSymbol(builtinTypeNames[6], CompletionKind.keyword);
	auto ubyte_ = makeSymbol(builtinTypeNames[20], CompletionKind.keyword);
	auto uint_ = makeSymbol(builtinTypeNames[1], CompletionKind.keyword);
	auto ulong_ = makeSymbol(builtinTypeNames[9], CompletionKind.keyword);
	auto ushort_ = makeSymbol(builtinTypeNames[7], CompletionKind.keyword);
	auto wchar_ = makeSymbol(builtinTypeNames[11], CompletionKind.keyword);

	auto alignof_ = makeSymbol("alignof", CompletionKind.keyword, null,
		"Size boundary the type needs to be aligned on.");
	auto mangleof_ = makeSymbol("mangleof", CompletionKind.keyword, null,
		"String representing the mangled representation of the type or symbol.");
	auto sizeof_ = makeSymbol("sizeof", CompletionKind.keyword, null,
		"Size of the type or expression in bytes.");
	auto stringof_ = makeSymbol("stringof", CompletionKind.keyword, null,
		"String representing the source representation of the type or expression; the expression is not evaluated.");
	auto init = makeSymbol("init", CompletionKind.keyword, null,
		"Default initializer value of the type.");
	auto min = makeSymbol("min", CompletionKind.keyword, null,
		"Smallest value of the enum members.");
	auto max = makeSymbol("max", CompletionKind.keyword, null,
		"Largest value of the enum members.");
	auto dup = makeSymbol("dup", CompletionKind.keyword, null,
		"Returns a newly allocated copy of the contents.");
	auto length = makeSymbol("length", CompletionKind.keyword, ulong_,
		"Number of elements (size_t). Can be set to resize a dynamic array; read-only for associative arrays.");
	auto tupleof = makeSymbol("tupleof", CompletionKind.keyword, null,
		"Symbol sequence of all the non-static fields, in declaration order.");

	offsetofSymbol = makeSymbol("offsetof", CompletionKind.keyword, null,
		"Offset in bytes of the field from the beginning of the struct, union, or class.");

	variadicTmpParamSymbol = makeSymbol("variadicTmpParam", CompletionKind.keyword);
	variadicTmpParamSymbol.addChild(init, false);
	variadicTmpParamSymbol.addChild(length, false);
	variadicTmpParamSymbol.addChild(stringof_, false);

	typeTmpParamSymbol = makeSymbol("typeTmpParam", CompletionKind.keyword);
	typeTmpParamSymbol.addChild(alignof_, false);
	typeTmpParamSymbol.addChild(init, false);
	typeTmpParamSymbol.addChild(mangleof_, false);
	typeTmpParamSymbol.addChild(sizeof_, false);
	typeTmpParamSymbol.addChild(stringof_, false);

	arraySymbols.insert(alignof_);
	arraySymbols.insert(dup);
	arraySymbols.insert(makeSymbol("idup", CompletionKind.keyword, null,
		"Returns a new array that is an immutable copy of the contents."));
	arraySymbols.insert(init);
	arraySymbols.insert(length);
	arraySymbols.insert(mangleof_);
	arraySymbols.insert(makeSymbol("ptr", CompletionKind.keyword, null,
		"Pointer to the first element of the array. Not accessible in @safe code."));
	arraySymbols.insert(sizeof_);
	arraySymbols.insert(stringof_);

	assocArraySymbols.insert(alignof_);
	assocArraySymbols.insert(makeSymbol("byKey", CompletionKind.keyword, null,
		"Returns a forward range enumerating the keys by reference."));
	assocArraySymbols.insert(makeSymbol("byValue", CompletionKind.keyword, null,
		"Returns a forward range enumerating the values by reference."));
	assocArraySymbols.insert(makeSymbol("clear", CompletionKind.keyword, null,
		"Removes all keys and values from the associative array."));
	assocArraySymbols.insert(dup);
	assocArraySymbols.insert(makeSymbol("get", CompletionKind.keyword, null,
		"Returns the value for a key, or a lazy default value if the key is not present."));
	assocArraySymbols.insert(init);
	assocArraySymbols.insert(makeSymbol("keys", CompletionKind.keyword, null,
		"Returns a newly allocated dynamic array containing copies of the keys."));
	assocArraySymbols.insert(length);
	assocArraySymbols.insert(mangleof_);
	assocArraySymbols.insert(makeSymbol("rehash", CompletionKind.keyword, null,
		"Reorganizes the associative array in place so that lookups are more efficient."));
	assocArraySymbols.insert(sizeof_);
	assocArraySymbols.insert(stringof_);
	assocArraySymbols.insert(init);
	assocArraySymbols.insert(makeSymbol("values", CompletionKind.keyword, null,
		"Returns a newly allocated dynamic array containing copies of the values."));

	DSymbol*[12] integralTypeArray;
	integralTypeArray[0] = bool_;
	integralTypeArray[1] = int_;
	integralTypeArray[2] = long_;
	integralTypeArray[3] = byte_;
	integralTypeArray[4] = char_;
	integralTypeArray[5] = dchar_;
	integralTypeArray[6] = short_;
	integralTypeArray[7] = ubyte_;
	integralTypeArray[8] = uint_;
	integralTypeArray[9] = ulong_;
	integralTypeArray[10] = ushort_;
	integralTypeArray[11] = wchar_;

	foreach (s; integralTypeArray)
	{
		s.addChild(makeSymbol("init", CompletionKind.keyword, s,
			"Default initializer value of the type."), false);
		s.addChild(makeSymbol("min", CompletionKind.keyword, s,
			"Minimum value representable by the type."), false);
		s.addChild(makeSymbol("max", CompletionKind.keyword, s,
			"Maximum value representable by the type."), false);
		s.addChild(alignof_, false);
		s.addChild(sizeof_, false);
		s.addChild(stringof_, false);
		s.addChild(mangleof_, false);
	}

	auto cdouble_ = makeSymbol(builtinTypeNames[21], CompletionKind.keyword);
	auto cent_ = makeSymbol(builtinTypeNames[15], CompletionKind.keyword);
	auto cfloat_ = makeSymbol(builtinTypeNames[22], CompletionKind.keyword);
	auto creal_ = makeSymbol(builtinTypeNames[23], CompletionKind.keyword);
	auto double_ = makeSymbol(builtinTypeNames[2], CompletionKind.keyword);
	auto float_ = makeSymbol(builtinTypeNames[4], CompletionKind.keyword);
	auto idouble_ = makeSymbol(builtinTypeNames[3], CompletionKind.keyword);
	auto ifloat_ = makeSymbol(builtinTypeNames[5], CompletionKind.keyword);
	auto ireal_ = makeSymbol(builtinTypeNames[18], CompletionKind.keyword);
	auto real_ = makeSymbol(builtinTypeNames[17], CompletionKind.keyword);
	auto ucent_ = makeSymbol(builtinTypeNames[16], CompletionKind.keyword);

	DSymbol*[11] floatTypeArray;
	floatTypeArray[0] = cdouble_;
	floatTypeArray[1] = cent_;
	floatTypeArray[2] = cfloat_;
	floatTypeArray[3] = creal_;
	floatTypeArray[4] = double_;
	floatTypeArray[5] = float_;
	floatTypeArray[6] = idouble_;
	floatTypeArray[7] = ifloat_;
	floatTypeArray[8] = ireal_;
	floatTypeArray[9] = real_;
	floatTypeArray[10] = ucent_;

	foreach (s; floatTypeArray)
	{
		s.addChild(alignof_, false);
		s.addChild(makeSymbol("dig", CompletionKind.keyword, s,
			"Number of decimal digits of precision."), false);
		s.addChild(makeSymbol("epsilon", CompletionKind.keyword, s,
			"Smallest increment to the value 1."), false);
		s.addChild(makeSymbol("infinity", CompletionKind.keyword, s,
			"Infinity value."), false);
		s.addChild(makeSymbol("init", CompletionKind.keyword, s,
			"Default initializer value of the type."), false);
		s.addChild(mangleof_, false);
		s.addChild(makeSymbol("mant_dig", CompletionKind.keyword, int_,
			"Number of bits in the mantissa."), false);
		s.addChild(makeSymbol("max", CompletionKind.keyword, s,
			"Maximum value representable by the type."), false);
		s.addChild(makeSymbol("max_10_exp", CompletionKind.keyword, int_,
			"Maximum int value such that 10^max_10_exp is representable."), false);
		s.addChild(makeSymbol("max_exp", CompletionKind.keyword, int_,
			"Maximum int value such that 2^(max_exp-1) is representable."), false);
		s.addChild(makeSymbol("min_exp", CompletionKind.keyword, int_,
			"Minimum int value such that 2^(min_exp-1) is representable as a normalized value."), false);
		s.addChild(makeSymbol("min_10_exp", CompletionKind.keyword, int_,
			"Minimum int value such that 10^min_10_exp is representable as a normalized value."), false);
		s.addChild(makeSymbol("min_normal", CompletionKind.keyword, s,
			"Smallest representable normalized value that's not 0."), false);
		s.addChild(makeSymbol("nan", CompletionKind.keyword, s,
			"NaN - Not a Number value."), false);
		s.addChild(sizeof_, false);
		s.addChild(stringof_, false);
	}

	aggregateSymbols.insert(tupleof);
	aggregateSymbols.insert(mangleof_);
	aggregateSymbols.insert(alignof_);
	aggregateSymbols.insert(sizeof_);
	aggregateSymbols.insert(stringof_);
	aggregateSymbols.insert(init);

	pointerSymbols.insert(mangleof_);
	pointerSymbols.insert(alignof_);
	pointerSymbols.insert(sizeof_);
	pointerSymbols.insert(stringof_);
	pointerSymbols.insert(init);

	classSymbols.insert(makeSymbol("classinfo", CompletionKind.variableName, null,
		"Information about the dynamic type of the class object (object.TypeInfo_Class)."));
	classSymbols.insert(tupleof);
	classSymbols.insert(makeSymbol("__vptr", CompletionKind.variableName, null,
		"Gives access to the class object's vtbl[]; should not be used in user code."));
	classSymbols.insert(makeSymbol("__monitor", CompletionKind.variableName, null,
		"The class object's monitor field; defined in druntime and excluded from .tupleof."));
	classSymbols.insert(mangleof_);
	classSymbols.insert(alignof_);
	classSymbols.insert(sizeof_);
	classSymbols.insert(stringof_);
	classSymbols.insert(init);

	enumSymbols.insert(init);
	enumSymbols.insert(sizeof_);
	enumSymbols.insert(alignof_);
	enumSymbols.insert(mangleof_);
	enumSymbols.insert(stringof_);
	enumSymbols.insert(min);
	enumSymbols.insert(max);


	ireal_.addChild(makeSymbol("im", CompletionKind.keyword, real_,
		"Imaginary part."), false);
	ifloat_.addChild(makeSymbol("im", CompletionKind.keyword, float_,
		"Imaginary part."), false);
	idouble_.addChild(makeSymbol("im", CompletionKind.keyword, double_,
		"Imaginary part."), false);
	ireal_.addChild(makeSymbol("re", CompletionKind.keyword, real_,
		"Real part."), false);
	ifloat_.addChild(makeSymbol("re", CompletionKind.keyword, float_,
		"Real part."), false);
	idouble_.addChild(makeSymbol("re", CompletionKind.keyword, double_,
		"Real part."), false);

	auto void_ = makeSymbol(builtinTypeNames[14], CompletionKind.keyword);

	builtinSymbols.insert(bool_);
	bool_.type = bool_;
	builtinSymbols.insert(int_);
	int_.type = int_;
	builtinSymbols.insert(long_);
	long_.type = long_;
	builtinSymbols.insert(byte_);
	byte_.type = byte_;
	builtinSymbols.insert(char_);
	char_.type = char_;
	builtinSymbols.insert(dchar_);
	dchar_.type = dchar_;
	builtinSymbols.insert(short_);
	short_.type = short_;
	builtinSymbols.insert(ubyte_);
	ubyte_.type = ubyte_;
	builtinSymbols.insert(uint_);
	uint_.type = uint_;
	builtinSymbols.insert(ulong_);
	ulong_.type = ulong_;
	builtinSymbols.insert(ushort_);
	ushort_.type = ushort_;
	builtinSymbols.insert(wchar_);
	wchar_.type = wchar_;
	builtinSymbols.insert(cdouble_);
	cdouble_.type = cdouble_;
	builtinSymbols.insert(cent_);
	cent_.type = cent_;
	builtinSymbols.insert(cfloat_);
	cfloat_.type = cfloat_;
	builtinSymbols.insert(creal_);
	creal_.type = creal_;
	builtinSymbols.insert(double_);
	double_.type = double_;
	builtinSymbols.insert(float_);
	float_.type = float_;
	builtinSymbols.insert(idouble_);
	idouble_.type = idouble_;
	builtinSymbols.insert(ifloat_);
	ifloat_.type = ifloat_;
	builtinSymbols.insert(ireal_);
	ireal_.type = ireal_;
	builtinSymbols.insert(real_);
	real_.type = real_;
	builtinSymbols.insert(ucent_);
	ucent_.type = ucent_;
	builtinSymbols.insert(void_);
	void_.type = void_;


	foreach (s; ["__DATE__", "__EOF__", "__TIME__", "__TIMESTAMP__", "__VENDOR__",
			"__VERSION__", "__FUNCTION__", "__PRETTY_FUNCTION__", "__MODULE__",
			"__FILE__", "__LINE__", "__FILE_FULL_PATH__"])
		builtinSymbols.insert(makeSymbol(s, CompletionKind.keyword));
}

static ~this()
{
	destroy(builtinSymbols);
	destroy(arraySymbols);
	destroy(assocArraySymbols);
	destroy(aggregateSymbols);
	destroy(classSymbols);
	destroy(enumSymbols);
	destroy(pointerSymbols);

	foreach (sym; symbolsMadeHere[])
		destroy(*sym);

	destroy(symbolsMadeHere);
	destroy(rba);
}

private RollbackAllocator rba;
private HashSet!(DSymbol*) symbolsMadeHere;

private DSymbol* makeSymbol(string s, CompletionKind kind, DSymbol* type = null,
	string documentation = null)
{
	auto sym = rba.make!DSymbol(istring(s), kind, type);
	sym.ownType = false;
	if (documentation !is null)
		sym.doc = DocString(istring(documentation));
	symbolsMadeHere.insert(sym);
	return sym;
}
private DSymbol* makeSymbol(istring s, CompletionKind kind, DSymbol* type = null,
	string documentation = null)
{
	auto sym = rba.make!DSymbol(s, kind, type);
	sym.ownType = false;
	if (documentation !is null)
		sym.doc = DocString(istring(documentation));
	symbolsMadeHere.insert(sym);
	return sym;
}
