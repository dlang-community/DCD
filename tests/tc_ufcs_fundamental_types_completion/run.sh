set -e
set -u

../../bin/dcd-client $1 -c24 file.d > actual_bool_test.txt
../../bin/dcd-client $1 -c50 file.d > actual_byte_test.txt
../../bin/dcd-client $1 -c78 file.d > actual_ubyte_test.txt
../../bin/dcd-client $1 -c106 file.d > actual_short_test.txt
../../bin/dcd-client $1 -c136 file.d > actual_ushort_test.txt
../../bin/dcd-client $1 -c160 file.d > actual_int_test.txt
../../bin/dcd-client $1 -c186 file.d > actual_uint_test.txt
../../bin/dcd-client $1 -c212 file.d > actual_long_test.txt
../../bin/dcd-client $1 -c240 file.d > actual_ulong_test.txt
../../bin/dcd-client $1 -c266 file.d > actual_cent_test.txt
../../bin/dcd-client $1 -c294 file.d > actual_ucent_test.txt
../../bin/dcd-client $1 -c320 file.d > actual_char_test.txt
../../bin/dcd-client $1 -c348 file.d > actual_wchar_test.txt
../../bin/dcd-client $1 -c376 file.d > actual_dchar_test.txt
../../bin/dcd-client $1 -c404 file.d > actual_float_test.txt
../../bin/dcd-client $1 -c434 file.d > actual_double_test.txt
../../bin/dcd-client $1 -c460 file.d > actual_real_test.txt
../../bin/dcd-client $1 -c490 file.d > actual_ifloat_test.txt
../../bin/dcd-client $1 -c522 file.d > actual_idouble_test.txt
../../bin/dcd-client $1 -c550 file.d > actual_ireal_test.txt
../../bin/dcd-client $1 -c580 file.d > actual_cfloat_test.txt
../../bin/dcd-client $1 -c612 file.d > actual_cdouble_test.txt
../../bin/dcd-client $1 -c640 file.d > actual_creal_test.txt
../../bin/dcd-client $1 -c666 file.d > actual_void_test.txt

diff actual_bool_test.txt expected_bool_test.txt
diff actual_byte_test.txt expected_byte_test.txt
diff actual_ubyte_test.txt expected_ubyte_test.txt
diff actual_short_test.txt expected_short_test.txt
diff actual_ushort_test.txt expected_ushort_test.txt
diff actual_int_test.txt expected_int_test.txt
diff actual_uint_test.txt expected_uint_test.txt
diff actual_long_test.txt expected_long_test.txt
diff actual_ulong_test.txt expected_ulong_test.txt
diff actual_cent_test.txt expected_cent_test.txt
diff actual_ucent_test.txt expected_ucent_test.txt
diff actual_char_test.txt expected_char_test.txt
diff actual_wchar_test.txt expected_wchar_test.txt
diff actual_dchar_test.txt expected_dchar_test.txt
diff actual_float_test.txt expected_float_test.txt
diff actual_double_test.txt expected_double_test.txt
diff actual_real_test.txt expected_real_test.txt
diff actual_ifloat_test.txt expected_ifloat_test.txt
diff actual_idouble_test.txt expected_idouble_test.txt
diff actual_ireal_test.txt expected_ireal_test.txt
diff actual_cfloat_test.txt expected_cfloat_test.txt
diff actual_cdouble_test.txt expected_cdouble_test.txt
diff actual_creal_test.txt expected_creal_test.txt
diff actual_void_test.txt expected_void_test.txt
