module dsymbol.builtin.symbols;

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

	auto alignof_ = makeSymbol("alignof", CompletionKind.keyword);
	auto mangleof_ = makeSymbol("mangleof", CompletionKind.keyword);
	auto sizeof_ = makeSymbol("sizeof", CompletionKind.keyword);
	auto stringof_ = makeSymbol("stringof", CompletionKind.keyword);
	auto init = makeSymbol("init", CompletionKind.keyword);
	auto min = makeSymbol("min", CompletionKind.keyword);
	auto max = makeSymbol("max", CompletionKind.keyword);
	auto dup = makeSymbol("dup", CompletionKind.keyword);
	auto length = makeSymbol("length", CompletionKind.keyword, ulong_);
	auto tupleof = makeSymbol("tupleof", CompletionKind.keyword);

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
	arraySymbols.insert(makeSymbol("idup", CompletionKind.keyword));
	arraySymbols.insert(init);
	arraySymbols.insert(length);
	arraySymbols.insert(mangleof_);
	arraySymbols.insert(makeSymbol("ptr", CompletionKind.keyword));
	arraySymbols.insert(sizeof_);
	arraySymbols.insert(stringof_);

	assocArraySymbols.insert(alignof_);
	assocArraySymbols.insert(makeSymbol("byKey", CompletionKind.keyword));
	assocArraySymbols.insert(makeSymbol("byValue", CompletionKind.keyword));
	assocArraySymbols.insert(makeSymbol("clear", CompletionKind.keyword));
	assocArraySymbols.insert(dup);
	assocArraySymbols.insert(makeSymbol("get", CompletionKind.keyword));
	assocArraySymbols.insert(init);
	assocArraySymbols.insert(makeSymbol("keys", CompletionKind.keyword));
	assocArraySymbols.insert(length);
	assocArraySymbols.insert(mangleof_);
	assocArraySymbols.insert(makeSymbol("rehash", CompletionKind.keyword));
	assocArraySymbols.insert(sizeof_);
	assocArraySymbols.insert(stringof_);
	assocArraySymbols.insert(init);
	assocArraySymbols.insert(makeSymbol("values", CompletionKind.keyword));

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
		s.addChild(makeSymbol("init", CompletionKind.keyword, s), false);
		s.addChild(makeSymbol("min", CompletionKind.keyword, s), false);
		s.addChild(makeSymbol("max", CompletionKind.keyword, s), false);
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
		s.addChild(makeSymbol("dig", CompletionKind.keyword, s), false);
		s.addChild(makeSymbol("epsilon", CompletionKind.keyword, s), false);
		s.addChild(makeSymbol("infinity", CompletionKind.keyword, s), false);
		s.addChild(makeSymbol("init", CompletionKind.keyword, s), false);
		s.addChild(mangleof_, false);
		s.addChild(makeSymbol("mant_dig", CompletionKind.keyword, int_), false);
		s.addChild(makeSymbol("max", CompletionKind.keyword, s), false);
		s.addChild(makeSymbol("max_10_exp", CompletionKind.keyword, int_), false);
		s.addChild(makeSymbol("max_exp", CompletionKind.keyword, int_), false);
		s.addChild(makeSymbol("min_exp", CompletionKind.keyword, int_), false);
		s.addChild(makeSymbol("min_10_exp", CompletionKind.keyword, int_), false);
		s.addChild(makeSymbol("min_normal", CompletionKind.keyword, s), false);
		s.addChild(makeSymbol("nan", CompletionKind.keyword, s), false);
		s.addChild(sizeof_, false);
		s.addChild(stringof_, false);
	}

	aggregateSymbols.insert(tupleof);
	aggregateSymbols.insert(mangleof_);
	aggregateSymbols.insert(alignof_);
	aggregateSymbols.insert(sizeof_);
	aggregateSymbols.insert(stringof_);
	aggregateSymbols.insert(init);

	classSymbols.insert(makeSymbol("classinfo", CompletionKind.variableName));
	classSymbols.insert(tupleof);
	classSymbols.insert(makeSymbol("__vptr", CompletionKind.variableName));
	classSymbols.insert(makeSymbol("__monitor", CompletionKind.variableName));
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


	ireal_.addChild(makeSymbol("im", CompletionKind.keyword, real_), false);
	ifloat_.addChild(makeSymbol("im", CompletionKind.keyword, float_), false);
	idouble_.addChild(makeSymbol("im", CompletionKind.keyword, double_), false);
	ireal_.addChild(makeSymbol("re", CompletionKind.keyword, real_), false);
	ifloat_.addChild(makeSymbol("re", CompletionKind.keyword, float_), false);
	idouble_.addChild(makeSymbol("re", CompletionKind.keyword, double_), false);

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

	foreach (sym; symbolsMadeHere[])
		destroy(*sym);

	destroy(symbolsMadeHere);
	destroy(rba);
}

private RollbackAllocator rba;
private HashSet!(DSymbol*) symbolsMadeHere;

private DSymbol* makeSymbol(string s, CompletionKind kind, DSymbol* type = null)
{
	import dparse.lexer : tok;

	auto sym = rba.make!DSymbol(istring(s), kind, type);
	sym.ownType = false;
	sym.protection = tok!"public";
	symbolsMadeHere.insert(sym);
	return sym;
}
private DSymbol* makeSymbol(istring s, CompletionKind kind, DSymbol* type = null)
{
	import dparse.lexer : tok;

	auto sym = rba.make!DSymbol(s, kind, type);
	sym.ownType = false;
	sym.protection = tok!"public";
	symbolsMadeHere.insert(sym);
	return sym;
}
