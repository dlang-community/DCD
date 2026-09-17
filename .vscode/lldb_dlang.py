# Based on https://github.com/vadimcn/vscode-lldb/blob/master/formatters/rust.py
from __future__ import print_function, division
import sys
import logging
import re
import lldb

if sys.version_info[0] == 2:
	# python2-based LLDB accepts utf8-encoded ascii strings only.
	to_lldb_str = lambda s: s.encode('utf8', 'backslashreplace') if isinstance(s, unicode) else s
	range = xrange
else:
	to_lldb_str = str

string_encoding = "escape" # remove | unicode | escape

log = logging.getLogger(__name__)

module = sys.modules[__name__]
d_category = None

def __lldb_init_module(debugger, dict):
	global d_category

	d_category = debugger.CreateCategory('D')
	d_category.SetEnabled(True)

	attach_synthetic_to_type(DAssocArrayPrinter, r'^_AArray_|[^0-9\[][^\[]*\]$', True)

	attach_synthetic_to_type(DSArrayPrinter, r'\[[0-9]+\]$', True)

	attach_synthetic_to_type(DArrayPrinter, r'^_Array_|\[\]$', True)

	attach_synthetic_to_type(DCStringPrinter, r'^_Array_char$|^_Array_char8_t$|^string$|^(const|immutable)?\(?char\)?\s*\[\]$', True)
	attach_synthetic_to_type(DWStringPrinter, r'^_Array_wchar_t$|^_Array_char16_t$|^wstring$|^(const|immutable)?\(?wchar\)?\s*\[\]$', True)
	attach_synthetic_to_type(DDStringPrinter, r'^_Array_dchar$|^dstring$|^(const|immutable)?\(?dchar\)?\s*\[\]$', True)
	
	attach_synthetic_to_type(DObjectPrinter, r' \*$', True)

def attach_synthetic_to_type(synth_class, type_name, is_regex=False):
	global module, d_category
	synth = lldb.SBTypeSynthetic.CreateWithClassName(__name__ + '.' + synth_class.__name__)
	synth.SetOptions(lldb.eTypeOptionCascade)
	ret = d_category.AddTypeSynthetic(lldb.SBTypeNameSpecifier(type_name, is_regex), synth)
	log.debug('attaching synthetic %s to "%s", is_regex=%s -> %s', synth_class.__name__, type_name, is_regex, ret)

	summary_fn = lambda valobj, dict: get_synth_summary(synth_class, valobj, dict)
	# LLDB accesses summary fn's by name, so we need to create a unique one.
	summary_fn.__name__ = '_get_synth_summary_' + synth_class.__name__
	setattr(module, summary_fn.__name__, summary_fn)
	attach_summary_to_type(summary_fn, type_name, is_regex)

def attach_summary_to_type(summary_fn, type_name, is_regex=False):
	global module, d_category
	summary = lldb.SBTypeSummary.CreateWithFunctionName(__name__ + '.' + summary_fn.__name__)
	summary.SetOptions(lldb.eTypeOptionCascade)
	ret = d_category.AddTypeSummary(lldb.SBTypeNameSpecifier(type_name, is_regex), summary)
	log.debug('attaching summary %s to "%s", is_regex=%s -> %s', summary_fn.__name__, type_name, is_regex, ret)

# 'get_summary' is annoyingly not a part of the standard LLDB synth provider API.
# This trick allows us to share data extraction logic between synth providers and their sibling summary providers.
def get_synth_summary(synth_class, valobj, dict):
	synth = synth_class(valobj.GetNonSyntheticValue(), dict)
	synth.update()
	summary = synth.get_summary()
	return to_lldb_str(summary)

def string_from_ptr(pointer, length, charsize, encoding):
	if length <= 0:
		return u''
	error = lldb.SBError()
	process = pointer.GetProcess()
	data = process.ReadMemory(pointer.GetValueAsUnsigned(), length * charsize, error)
	if error.Success():
		return data.decode(encoding, 'backslashreplace')
	else:
		log.error('ReadMemory error: %s', error.GetCString())

def get_obj_summary(valobj, unavailable='{...}'):
	summary = valobj.GetSummary()
	if summary is not None:
		return summary
	summary = valobj.GetValue()
	if summary is not None:
		return summary
	return unavailable

def sequence_summary(array, clipsize=32, maxsize=100, shownames=False):
	s = ''
	for i in range(array.num_children()):
		if i > 0: s += ', '
		if len(s) >= clipsize:
			s += '...'
			break
		child = array.get_child_at_index(i)
		if child == None:
			s += '<None>'
		else:
			if shownames:
				s += child.name + ' = '
			s += get_obj_summary(child)
	if len(s) > maxsize:
		return '...'
	return s

def get_array_summary(valobj):
	return '[%d] {%s}' % (valobj.num_children(), sequence_summary(valobj))

def get_map_summary(valobj):
	return '[%d] {%s}' % (valobj.num_children(), sequence_summary(valobj, shownames=True))

class BaseSynthProvider(object):
	def __init__(self, valobj, dict={}):
		self.valobj = valobj
		self.initialize()
	def initialize(self):
		return None
	def update(self):
		return False
	def num_children(self):
		return 0
	def has_children(self):
		return False
	def get_child_at_index(self, index):
		return None
	def get_child_index(self, name):
		return None
	def get_summary(self):
		return None

class DSArrayPrinter(BaseSynthProvider):
	"print D static arrays"
	def num_children(self):
		return self.valobj.GetNumChildren()

	def get_child_at_index(self, index):
		return self.valobj.GetChildAtIndex(index)

	def get_summary(self):
			return get_array_summary(self)

class DArrayPrinter(BaseSynthProvider):
	"print D arrays"

	def initialize(self):
		ptr, length = self.ptr_and_length(self.valobj)
		self.ptr = ptr
		self.length = length
		self.item_type = self.ptr.GetType().GetPointeeType()
		self.item_size = self.item_type.GetByteSize()

	def ptr_and_length(self, val):
		return (
			self.valobj.GetChildMemberWithName("ptr"),
			self.valobj.GetChildMemberWithName("length").GetValueAsUnsigned()
		)

	def num_children(self):
		return self.length

	def has_children(self):
		return True

	def get_child_at_index(self, index):
		try:
			if not 0 <= index < self.length:
				return None
			offset = index * self.item_size
			return self.ptr.CreateChildAtOffset('[%s]' % index, offset, self.item_type)
		except Exception as e:
			log.error('%s', e)
			raise

	def get_child_index(self, name):
		try:
			return int(name.lstrip('[').rstrip(']'))
		except Exception as e:
			log.error('%s', e)
			raise

	def get_summary(self):
		return '&' + get_array_summary(self)

class DBaseStringPrinter(DArrayPrinter):
	def get_child_at_index(self, index):
		ch = DArrayPrinter.get_child_at_index(self, index)
		ch.SetFormat(self.get_format())
		return ch

	def has_children(self):
		return False

	def get_format(self):
		return lldb.eFormatUnicode8 # abstract

	def get_charsize(self):
		return 1 # abstract

	def get_encoding(self):
		return "utf8" # abstract

	def get_suffix(self):
		return ""

	def get_summary(self):
		# original code used string length limit to avoid garbage from uninitialized values
		# this issue is less common in D, but it's good practice for the rare cases anyway.
		strval = string_from_ptr(self.ptr, min(self.length, 10000), self.get_charsize(), self.get_encoding())
		global log
		if strval == None:
			return None
		if self.length > 10000: strval += u'...'
		return (u'"%s"' % escape_string(strval)) + self.get_suffix()

class DCStringPrinter(DBaseStringPrinter):
	"print D string values"

class DWStringPrinter(DBaseStringPrinter):
	"print D wstring values"

	def get_format(self):
		return lldb.eFormatUnicode16

	def get_charsize(self):
		return 2

	def get_encoding(self):
		return "utf16"

	def get_suffix(self):
		return "w"

class DDStringPrinter(DBaseStringPrinter):
	"print D dstring values"

	def get_format(self):
		return lldb.eFormatUnicode32

	def get_charsize(self):
		return 4

	def get_encoding(self):
		return "utf32"

	def get_suffix(self):
		return "d"

class DAssocArrayPrinter(BaseSynthProvider):
	"print D arrays"

	def initialize(self):
		self.target = self.valobj.target
		self.voidPtr = self.target.FindFirstType("void").GetPointerType()
		self.ptr = self.valobj.GetChildMemberWithName("ptr").Cast(self.voidPtr)
		tag = self.valobj.type.name
		if tag != None:
			if tag.startswith("_AArray_"):
				self.parse_types_dmd(tag)
			elif tag.endswith("]"):
				self.parse_types_ldc(tag)

	def parse_types_dmd(self, tag):
		# splits an AA type like _AArray_ucent_int into key & value
		tag = tag[8:]
		# https://github.com/dlang/dmd/blob/7a0382177f35b2766c2d0ba60dae5e541d8033e0/src/dmd/backend/var.d#L297
		if tag.startswith('_'):
			# types might start with _, but there is no type starting with _ which is less than 3 characters long
			# so we start searching for _ starting on the 3rd character
			split_loc = tag.find('_', 2)
		else:
			split_loc = tag.find('_')

		self.key_type = self.voidPtr
		self.value_type = self.voidPtr

		if split_loc != -1:
			# however some types end with _t, so we need to offset the splitter by 2
			if tag[split_loc:].startswith('_t_'):
				split_loc += 2

			key_str = tag[0:split_loc]
			value_str = tag[(split_loc+1):]
			if key_str != 'key':
				self.key_type = parse_dmd_type(self.target, key_str)
			if value_str != 'value':
				self.value_type = parse_dmd_type(self.target, value_str)

	def parse_types_ldc(self, tag):
		key_start = len(tag)
		depth = 0
		while key_start >= 0:
			key_start -= 1
			if tag[key_start] == ']':
				depth += 1
			elif tag[key_start] == '[':
				depth -= 1
			if depth == 0:
				break
		self.value_type = parse_d_type(self.target, tag[:key_start])
		self.key_type = parse_d_type(self.target, tag[(key_start+1):-1])

	# assumed ABI:
	# struct AA
	#   Bucket[] buckets
	#   uint used
	#   uint deleted
	#   void* entryTI
	#   uint firstUsed
	#   uint keysz
	#   uint valsz
	#   uint valoff
	#   ubyte flags
	#
	# struct Bucket (align 16)
	#   size_t hash
	#   void* entry

	def lookup_type(self, name):
		return self.target.FindFirstType(name)

	def used(self):
		return self.ptr.CreateChildAtOffset("used", self.lookup_type("size_t").size * 2, self.lookup_type("int")).unsigned

	def deleted(self):
		return self.ptr.CreateChildAtOffset("deleted", self.lookup_type("size_t").size * 2 + self.lookup_type("int").size, self.lookup_type("int")).unsigned

	def valoff(self):
		return self.ptr.CreateChildAtOffset("valoff", self.lookup_type("size_t").size * 3 + self.lookup_type("int").size * 5, self.lookup_type("int")).unsigned

	def buckets(self):
		"returns an iterator of bucket pointers"

		length = self.ptr.Cast(self.lookup_type("size_t").GetPointerType()).Dereference().unsigned
		bucketptr = self.ptr.CreateChildAtOffset("bucketptr", self.lookup_type("size_t").size, self.voidPtr)
		bucketsize = self.bucket_size()

		for i in range(length):
			yield bucketptr.CreateChildAtOffset("bucketptr", i * bucketsize, self.voidPtr).AddressOf()

	def bucket_filled(self, bucket):
		hashval = bucket.CreateChildAtOffset("hashval", 0, self.lookup_type("size_t")).unsigned
		HASH_FILLED_MARK = 1 << (8 * self.lookup_type("size_t").size) - 1
		return hashval & HASH_FILLED_MARK != 0

	def bucket_entry(self, bucket):
		return bucket.CreateChildAtOffset("bucket_entry", self.lookup_type("size_t").size, self.voidPtr.GetPointerType())

	def bucket_size(self):
		return self.voidPtr.size + self.lookup_type("size_t").size

	def child_iter(self):
		for bucket in self.buckets():
			if self.bucket_filled(bucket):
				yield self.bucket_entry(bucket)

	def num_children(self):
		return self.used() - self.deleted()

	def has_children(self):
		return self.num_children() > 0 #self.ptr.unsigned != 0

	def get_key_name(self, child, index):
		key = child.CreateChildAtOffset('[%s]' % index, 0, self.key_type)
		summary = get_obj_summary(key)
		if key.error.Fail():
			summary = '[(void*) %s]' % str(child.addr)
		return summary

	def get_child_at_index(self, index):
		try:
			remaining = index
			for child in self.child_iter():
				if remaining == 0:
					summary = self.get_key_name(child, index)
					if self.value_type.name == "void":
						return child.CreateChildAtOffset(summary, self.valoff(), self.voidPtr).AddressOf().Cast(self.voidPtr)
					else:
						return child.CreateChildAtOffset(summary, self.valoff(), self.value_type)
				else:
					remaining -= 1

			log.error("not found index %s, remaining %s, len: %s", index, remaining, self.num_children())
			return None
		except Exception as e:
			log.error('%s', e)
			raise

	def get_child_index(self, name):
		try:
			index = 0
			for child in self.child_iter():
				if self.get_key_name(child, index) == name:
					return index
				index += 1
			return None
		except Exception as e:
			log.error('%s', e)
			raise

	def get_summary(self):
		return get_map_summary(self)


def is_ptr_to_class(valobj):
	''' type of dereferenced value is a:
			class if directbaseclass > 0
			interface if bytesize == 0 (using DMD, LDC uses 8 bytes)
			primitivie otherwise
	'''
	return bool(valobj.Dereference().GetType().GetNumberOfDirectBaseClasses() > 0)

class DObjectPrinter(BaseSynthProvider):
	def initialize(self):
		pass

	def update(self):
		try:
			self._update()
		except Exception as e:
			log.error('%s', e)
			raise

	def _update(self):
		type_name = self.valobj.GetTypeName()
		if type_name in ['unsigned long *', 'void *'] or type_name.endswith('**'):
			return

		if self.valobj.GetName().startswith('*'):
			# stop recursion when dereferencing values
			return
	
		if is_ptr_to_class(self.valobj):
			# print('should be class:',self.valobj.GetTypeName())
			valobj = self.get_dynamic_value_from_address(self.valobj.GetValueAsUnsigned())
			if valobj is None:
				log.debug("couldn't get dynamic value from type %s", self.valobj.GetTypeName())
				return

			self.valobj = valobj
			self.set_type_name(self.valobj)
			return

		# print('is not a class:',self.valobj.GetTypeName())
		interface_type = self.valobj.GetType().GetPointeeType()
		if interface_type.GetByteSize() not in [0,8]:
			# interfaces size in dmd:0, ldc:8. Should filter out some false positives.
			return

		target = self.valobj.target
		
		# object of any interface I (technically I* b/c reference semantics) can be cast into Interface***

		address = self.valobj.Cast(target.FindFirstType("void").GetPointerType().GetPointerType().GetPointerType())
		interface_struct_address = address.Dereference().Dereference().GetValueAsUnsigned()

		# Interface has field 'offset' at relative location 0x18
		offset_address = interface_struct_address + 0x18
		offset = self.valobj.CreateValueFromAddress("offset_ptr", offset_address, target.FindFirstType("ulong").GetPointerType())


		# offset is relative location between interface and object pointer
		# object pointer can be cast into TypeInfo_Class**
		# TypeInfo_Class has field 'name' at relative location 0x20
		object_address = address.GetValueAsUnsigned() - offset.GetValueAsUnsigned()

		dynamic_value= self.get_dynamic_value_from_address(object_address)
		if dynamic_value:
			# if not then value was not an interface to begin with
			self.valobj = dynamic_value	

		self.set_type_name(self.valobj)

	def set_type_name(self, value):
		self.type_name = self.valobj.GetTypeName()
		if '!' in self.type_name:
			# template type names have a constant Suffix, i.e. mymodule.MyGenericType!int.Template
			self.type_name = self.type_name[0:-9]



	def get_dynamic_value_from_address(self, address):
		target: lldb.SBTarget = self.valobj.GetTarget()
		void_ptr_type:lldb.SBType = target.FindFirstType("void").GetPointerType()

		typeinfo_class = self.valobj.CreateValueFromAddress("obj_ptr", address,void_ptr_type.GetPointerType())
		# TypeInfo_Class has field 'name' at relative location 0x20
		tic_address = typeinfo_class.Dereference().GetValueAsUnsigned() 
		if not tic_address:
			return
		name_address = tic_address + 0x20
		name_value = self.valobj.CreateValueFromAddress("class_name", name_address, target.FindFirstType("string"))
		name = (name_value.GetSummary() or '').strip('"')
		if not name:
			return
		
		tpObject = target.FindFirstType(name)
		if not tpObject and '.' not in name:
			# dmd: 'object' module is implicitly imported
			tpObject = target.FindFirstType('object.' + name)
		
		if not tpObject and '.' in name:
			# ldc: doesn't find types prefixed with e.g. 'object.'
			last_idx = name.rfind('.')
			tpObject = target.FindFirstType(name[last_idx+1:])

		if not tpObject:
			# TODO: LDC does not publish types unless they are used as static type
			# print('could not find type', name)
			log.error('could not find type %s', name)
			return

		return self.valobj.CreateValueFromAddress('', address, tpObject)
	
	def num_children(self):
		return self.valobj.GetNumChildren()

	def has_children(self):
		return self.valobj.GetNumChildren() > 0

	def get_child_at_index(self, index):
		return self.valobj.GetChildAtIndex(index)

	def get_child_index(self, name):
		return self.valobj.GetIndexOfChildWithName(name)

	def get_summary(self):
		if getattr(self, 'type_name', ''):
			return self.type_name

		try:
			tpVoidPtr = self.valobj.target.FindFirstType("void").GetPointerType()
			addr= self.valobj.Cast(tpVoidPtr).GetValueAsUnsigned()
			if not addr:
				return '%s(null)' % self.valobj.GetTypeName()
			return '%s(0x%016x)' % (self.valobj.GetTypeName(), addr)
		except Exception as e:
			log.error('%s', e)	
			raise	


control_character_finder = re.compile(r'[\x00-\x1F]')
escaped_characters = re.compile(r'[\\"]')
def escape_string(str):
	global string_encoding
	global control_character_finder
	global escaped_characters

	if string_encoding == "remove":
		return control_character_finder.sub('', str)
	elif string_encoding == "unicode":
		return control_character_finder.sub(lambda m: chr(ord(m.group()) + 0x2400), str)
	elif string_encoding == "escape":
		special_encodings = {
			0x00: r'\0',
			0x07: r'\a',
			0x08: r'\b',
			0x09: r'\t',
			0x0C: r'\f',
			0x0A: r'\n',
			0x0B: r'\v',
			0x0D: r'\r',
		}
		str = escaped_characters.sub(r'\\\g<0>', str)
		return control_character_finder.sub(lambda m: special_encodings.get(ord(m.group()), r'\x%02x' % ord(m.group())), str)
	else:
		return str

def parse_d_type(target, type):
	return target.FindFirstType(type)

def parse_dmd_type(target, type):
	return {
		"bool": target.FindFirstType("bool"),
		"char": target.FindFirstType("char"),
		"signed char": target.FindFirstType("ubyte"),
		"unsigned char": target.FindFirstType("ubyte"),
		"char8_t": target.FindFirstType("char"),
		"char16_t": target.FindFirstType("wchar_t"),
		"short": target.FindFirstType("short"),
		"wchar_t": target.FindFirstType("wchar_t"),
		"unsigned short": target.FindFirstType("short"),
		"enum": target.FindFirstType("int"),
		"int": target.FindFirstType("int"),
		"unsigned": target.FindFirstType("int"),
		"long": target.FindFirstType("int"),
		"unsigned long": target.FindFirstType("int"),
		"dchar": target.FindFirstType("dchar"),
		"long long": target.FindFirstType("long"),
		"uns long long": target.FindFirstType("long"),
		"cent": target.FindFirstType("void"),
		"ucent": target.FindFirstType("void"),
		"float": target.FindFirstType("float"),
		"double": target.FindFirstType("double"),
		"double alias": target.FindFirstType("double"),
		"long double": target.FindFirstType("long double"),
		"imaginary float": target.FindFirstType("float"),
		"imaginary double": target.FindFirstType("double"),
		"imaginary long double": target.FindFirstType("long double"),
		"complex float": target.FindFirstType("__complex float"),
		"complex double": target.FindFirstType("__complex double"),
		"complex long double": target.FindFirstType("__complex long double"),
		"float[4]": target.FindFirstType("float").GetArrayType(4),
		"double[2]": target.FindFirstType("double").GetArrayType(2),
		"signed char[16]": target.FindFirstType("ubyte").GetArrayType(16),
		"unsigned char[16]": target.FindFirstType("ubyte").GetArrayType(16),
		"short[8]": target.FindFirstType("short").GetArrayType(8),
		"unsigned short[8]": target.FindFirstType("short").GetArrayType(8),
		"long[4]": target.FindFirstType("int").GetArrayType(4),
		"unsigned long[4]": target.FindFirstType("int").GetArrayType(4),
		"long long[2]": target.FindFirstType("long").GetArrayType(2),
		"unsigned long long[2]": target.FindFirstType("long").GetArrayType(2),
		"float[8]": target.FindFirstType("float").GetArrayType(8),
		"double[4]": target.FindFirstType("double").GetArrayType(4),
		"signed char[32]": target.FindFirstType("ubyte").GetArrayType(32),
		"unsigned char[32]": target.FindFirstType("ubyte").GetArrayType(32),
		"short[16]": target.FindFirstType("short").GetArrayType(16),
		"unsigned short[16]": target.FindFirstType("short").GetArrayType(16),
		"long[8]": target.FindFirstType("int").GetArrayType(8),
		"unsigned long[8]": target.FindFirstType("int").GetArrayType(8),
		"long long[4]": target.FindFirstType("long").GetArrayType(4),
		"unsigned long long[4]": target.FindFirstType("long").GetArrayType(4),
		"float[16]": target.FindFirstType("float").GetArrayType(16),
		"double[8]": target.FindFirstType("double").GetArrayType(8),
		"signed char[64]": target.FindFirstType("ubyte").GetArrayType(64),
		"unsigned char[64]": target.FindFirstType("ubyte").GetArrayType(64),
		"short[32]": target.FindFirstType("short").GetArrayType(32),
		"unsigned short[32]": target.FindFirstType("short").GetArrayType(32),
		"long[16]": target.FindFirstType("int").GetArrayType(16),
		"unsigned long[16]": target.FindFirstType("int").GetArrayType(16),
		"long long[8]": target.FindFirstType("long").GetArrayType(8),
		"unsigned long long[8]": target.FindFirstType("long").GetArrayType(8),
		"nullptr_t": target.FindFirstType("void"),
		"*": target.FindFirstType("void").GetPointerType(),
		"&": target.FindFirstType("void").GetReferenceType(),
		"void": target.FindFirstType("void"),
		"noreturn": target.FindFirstType("void"),
		"struct": target.FindFirstType("void"),
		"array": target.FindFirstType("void"),
		"C func": target.FindFirstType("void").GetPointerType(),
		"Pascal func": target.FindFirstType("void").GetPointerType(),
		"std func": target.FindFirstType("void").GetPointerType(),
		"*": target.FindFirstType("void").GetPointerType(),
		"member func": target.FindFirstType("void").GetPointerType(),
		"D func": target.FindFirstType("void").GetPointerType(),
		"C func": target.FindFirstType("void").GetPointerType(),
		"__near &": target.FindFirstType("void").GetReferenceType(),
		"__ss *": target.FindFirstType("void").GetPointerType(),
		"__cs *": target.FindFirstType("void").GetPointerType(),
		"__far16 *": target.FindFirstType("void").GetPointerType(),
		"__far *": target.FindFirstType("void").GetPointerType(),
		"__huge *": target.FindFirstType("void").GetPointerType(),
		"__handle *": target.FindFirstType("void").GetPointerType(),
		"__immutable *": target.FindFirstType("void").GetPointerType(),
		"__shared *": target.FindFirstType("void").GetPointerType(),
		"__restrict *": target.FindFirstType("void").GetPointerType(),
		"__fg *": target.FindFirstType("void").GetPointerType(),
		"far C func": target.FindFirstType("void").GetPointerType(),
		"far Pascal func": target.FindFirstType("void").GetPointerType(),
		"far std func": target.FindFirstType("void").GetPointerType(),
		"_far16 Pascal func": target.FindFirstType("void").GetPointerType(),
		"sys func": target.FindFirstType("void").GetPointerType(),
		"far sys func": target.FindFirstType("void").GetPointerType(),
		"__far &": target.FindFirstType("void").GetReferenceType(),
		"interrupt func": target.FindFirstType("void").GetPointerType(),
		"memptr": target.FindFirstType("void").GetPointerType(),
		"ident": target.FindFirstType("void"),
		"template": target.FindFirstType("void"),
		"vtshape": target.FindFirstType("void"),
	}.get(type, "void")
