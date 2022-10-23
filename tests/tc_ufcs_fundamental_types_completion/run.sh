set -e
#set -u

../../bin/dcd-client $1 -c24 file.d > test_bool_actual.txt
../../bin/dcd-client $1 -c50 file.d > test_byte_actual.txt
../../bin/dcd-client $1 -c78 file.d > test_ubyte_actual.txt
../../bin/dcd-client $1 -c106 file.d > test_short_actual.txt
../../bin/dcd-client $1 -c136 file.d > test_ushort_actual.txt
../../bin/dcd-client $1 -c160 file.d > test_int_actual.txt
../../bin/dcd-client $1 -c186 file.d > test_uint_actual.txt
../../bin/dcd-client $1 -c212 file.d > test_long_actual.txt
../../bin/dcd-client $1 -c240 file.d > test_ulong_actual.txt
../../bin/dcd-client $1 -c266 file.d > test_cent_actual.txt
../../bin/dcd-client $1 -c294 file.d > test_ucent_actual.txt
../../bin/dcd-client $1 -c320 file.d > test_char_actual.txt
../../bin/dcd-client $1 -c348 file.d > test_wchar_actual.txt
../../bin/dcd-client $1 -c376 file.d > test_dchar_actual.txt
../../bin/dcd-client $1 -c404 file.d > test_float_actual.txt
../../bin/dcd-client $1 -c434 file.d > test_double_actual.txt
../../bin/dcd-client $1 -c460 file.d > test_real_actual.txt
../../bin/dcd-client $1 -c490 file.d > test_ifloat_actual.txt
../../bin/dcd-client $1 -c522 file.d > test_idouble_actual.txt
../../bin/dcd-client $1 -c550 file.d > test_ireal_actual.txt
../../bin/dcd-client $1 -c580 file.d > test_cfloat_actual.txt
../../bin/dcd-client $1 -c612 file.d > test_cdouble_actual.txt
../../bin/dcd-client $1 -c640 file.d > test_creal_actual.txt
../../bin/dcd-client $1 -c666 file.d > test_void_actual.txt

diff test_bool_actual.txt test_bool_expected.txt 
diff test_byte_actual.txt test_byte_expected.txt
diff test_ubyte_actual.txt test_ubyte_expected.txt
diff test_short_actual.txt test_short_expected.txt
diff test_ushort_actual.txt test_ushort_expected.txt
diff test_int_actual.txt test_int_expected.txt
diff test_uint_actual.txt test_uint_expected.txt
diff test_long_actual.txt test_long_expected.txt
diff test_ulong_actual.txt test_ulong_expected.txt
diff test_cent_actual.txt test_cent_expected.txt
diff test_ucent_actual.txt test_ucent_expected.txt
diff test_char_actual.txt test_char_expected.txt
diff test_wchar_actual.txt test_wchar_expected.txt
diff test_dchar_actual.txt test_dchar_expected.txt
diff test_float_actual.txt test_float_expected.txt
diff test_double_actual.txt test_double_expected.txt
diff test_real_actual.txt test_real_expected.txt
diff test_ifloat_actual.txt test_ifloat_expected.txt
diff test_idouble_actual.txt test_idouble_expected.txt
diff test_ireal_actual.txt test_ireal_expected.txt
diff test_cfloat_actual.txt test_cfloat_expected.txt
diff test_cdouble_actual.txt test_cdouble_expected.txt
diff test_creal_actual.txt test_creal_expected.txt
diff test_void_actual.txt test_void_expected.txt
