set -e
set -u

# Structural UFCS template deduction: `T*` matches an `int*` receiver,
# `T[]` matches an `int[]` receiver; nested wrappers (`int**`, `int[]*`)
# and constrained parameters must NOT match.
../../bin/dcd-client $1 -c271 file.d > actual_ptr_test.txt
../../bin/dcd-client $1 -c307 file.d > actual_arr_test.txt
../../bin/dcd-client $1 -c356 file.d > actual_ptrptr_test.txt
../../bin/dcd-client $1 -c404 file.d > actual_arrptr_test.txt

diff actual_ptr_test.txt expected_ptr_test.txt
diff actual_arr_test.txt expected_arr_test.txt
diff actual_ptrptr_test.txt expected_ptrptr_test.txt
diff actual_arrptr_test.txt expected_arrptr_test.txt
