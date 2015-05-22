module dsymbol.builtin.symbols;

import dsymbol.symbol;
import dsymbol.builtin.names;
import dsymbol.string_interning;
import containers.ttree;
import std.allocator;
import std.d.lexer;

/**
 * Symbols for the built in types
 */
TTree!(DSymbol*, true, "a < b", false) builtinSymbols;

/**
 * Array properties
 */
TTree!(DSymbol*, true, "a < b", false) arraySymbols;

/**
 * Associative array properties
 */
TTree!(DSymbol*, true, "a < b", false) assocArraySymbols;

/**
 * Struct, enum, union, class, and interface properties
 */
TTree!(DSymbol*, true, "a < b", false) aggregateSymbols;

/**
 * Class properties
 */
TTree!(DSymbol*, true, "a < b", false) classSymbols;

static this()
{
	auto bool_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[13], CompletionKind.keyword);
	auto int_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[0], CompletionKind.keyword);
	auto long_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[8], CompletionKind.keyword);
	auto byte_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[19], CompletionKind.keyword);
	auto char_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[10], CompletionKind.keyword);
	auto dchar_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[12], CompletionKind.keyword);
	auto short_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[6], CompletionKind.keyword);
	auto ubyte_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[20], CompletionKind.keyword);
	auto uint_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[1], CompletionKind.keyword);
	auto ulong_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[9], CompletionKind.keyword);
	auto ushort_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[7], CompletionKind.keyword);
	auto wchar_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[11], CompletionKind.keyword);

	auto alignof_ = allocate!DSymbol(Mallocator.it, internString("alignof"), CompletionKind.keyword);
	auto mangleof_ = allocate!DSymbol(Mallocator.it, internString("mangleof"), CompletionKind.keyword);
	auto sizeof_ = allocate!DSymbol(Mallocator.it, internString("sizeof"), CompletionKind.keyword);
	auto stringof_ = allocate!DSymbol(Mallocator.it, internString("init"), CompletionKind.keyword);
	auto init = allocate!DSymbol(Mallocator.it, internString("stringof"), CompletionKind.keyword);

	arraySymbols.insert(alignof_);
	arraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("dup"), CompletionKind.keyword));
	arraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("idup"), CompletionKind.keyword));
	arraySymbols.insert(init);
	arraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("length"), CompletionKind.keyword, ulong_));
	arraySymbols.insert(mangleof_);
	arraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("ptr"), CompletionKind.keyword));
	arraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("reverse"), CompletionKind.keyword));
	arraySymbols.insert(sizeof_);
	arraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("sort"), CompletionKind.keyword));
	arraySymbols.insert(stringof_);

	assocArraySymbols.insert(alignof_);
	assocArraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("byKey"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("byValue"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("dup"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("get"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("init"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("keys"), CompletionKind.keyword));
	assocArraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("length"), CompletionKind.keyword, ulong_));
	assocArraySymbols.insert(mangleof_);
	assocArraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("rehash"), CompletionKind.keyword));
	assocArraySymbols.insert(sizeof_);
	assocArraySymbols.insert(stringof_);
	assocArraySymbols.insert(init);
	assocArraySymbols.insert(allocate!DSymbol(Mallocator.it, internString("values"), CompletionKind.keyword));

	DSymbol*[11] integralTypeArray;
	integralTypeArray[0] = bool_;
	integralTypeArray[1] = int_;
	integralTypeArray[2] = long_;
	integralTypeArray[3] = byte_;
	integralTypeArray[4] = char_;
	integralTypeArray[4] = dchar_;
	integralTypeArray[5] = short_;
	integralTypeArray[6] = ubyte_;
	integralTypeArray[7] = uint_;
	integralTypeArray[8] = ulong_;
	integralTypeArray[9] = ushort_;
	integralTypeArray[10] = wchar_;

	foreach (s; integralTypeArray)
	{
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("init"), CompletionKind.keyword, s));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("min"), CompletionKind.keyword, s));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("max"), CompletionKind.keyword, s));
		s.parts.insert(alignof_);
		s.parts.insert(sizeof_);
		s.parts.insert(stringof_);
		s.parts.insert(mangleof_);
		s.parts.insert(init);
	}

	auto cdouble_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[21], CompletionKind.keyword);
	auto cent_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[15], CompletionKind.keyword);
	auto cfloat_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[22], CompletionKind.keyword);
	auto creal_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[23], CompletionKind.keyword);
	auto double_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[2], CompletionKind.keyword);
	auto float_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[4], CompletionKind.keyword);
	auto idouble_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[3], CompletionKind.keyword);
	auto ifloat_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[5], CompletionKind.keyword);
	auto ireal_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[18], CompletionKind.keyword);
	auto real_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[17], CompletionKind.keyword);
	auto ucent_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[16], CompletionKind.keyword);

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
		s.parts.insert(alignof_);
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("dig"), CompletionKind.keyword, s));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("epsilon"), CompletionKind.keyword, s));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("infinity"), CompletionKind.keyword, s));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("init"), CompletionKind.keyword, s));
		s.parts.insert(mangleof_);
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("mant_dig"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("max"), CompletionKind.keyword, s));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("max_10_exp"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("max_exp"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("min"), CompletionKind.keyword, s));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("min_exp"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("min_10_exp"), CompletionKind.keyword, int_));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("min_normal"), CompletionKind.keyword, s));
		s.parts.insert(allocate!DSymbol(Mallocator.it, internString("nan"), CompletionKind.keyword, s));
		s.parts.insert(sizeof_);
		s.parts.insert(stringof_);
	}

	aggregateSymbols.insert(allocate!DSymbol(Mallocator.it, internString("tupleof"), CompletionKind.keyword));
	aggregateSymbols.insert(mangleof_);
	aggregateSymbols.insert(alignof_);
	aggregateSymbols.insert(sizeof_);
	aggregateSymbols.insert(stringof_);
	aggregateSymbols.insert(init);

	classSymbols.insert(allocate!DSymbol(Mallocator.it, internString("classInfo"), CompletionKind.variableName));
	classSymbols.insert(allocate!DSymbol(Mallocator.it, internString("tupleof"), CompletionKind.variableName));
	classSymbols.insert(allocate!DSymbol(Mallocator.it, internString("__vptr"), CompletionKind.variableName));
	classSymbols.insert(allocate!DSymbol(Mallocator.it, internString("__monitor"), CompletionKind.variableName));
	classSymbols.insert(mangleof_);
	classSymbols.insert(alignof_);
	classSymbols.insert(sizeof_);
	classSymbols.insert(stringof_);
	classSymbols.insert(init);

	ireal_.parts.insert(allocate!DSymbol(Mallocator.it, internString("im"), CompletionKind.keyword, real_));
	ifloat_.parts.insert(allocate!DSymbol(Mallocator.it, internString("im"), CompletionKind.keyword, float_));
	idouble_.parts.insert(allocate!DSymbol(Mallocator.it, internString("im"), CompletionKind.keyword, double_));
	ireal_.parts.insert(allocate!DSymbol(Mallocator.it, internString("re"), CompletionKind.keyword, real_));
	ifloat_.parts.insert(allocate!DSymbol(Mallocator.it, internString("re"), CompletionKind.keyword, float_));
	idouble_.parts.insert(allocate!DSymbol(Mallocator.it, internString("re"), CompletionKind.keyword, double_));

	auto void_ = allocate!DSymbol(Mallocator.it, builtinTypeNames[14], CompletionKind.keyword);

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
			"__FILE__", "__LINE__"])
		builtinSymbols.insert(allocate!DSymbol(Mallocator.it, internString(s), CompletionKind.keyword));
}
