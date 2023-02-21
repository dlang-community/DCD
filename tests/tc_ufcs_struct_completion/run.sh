set -e
set -u

../../bin/dcd-client $1 -c82 -I"$PWD"/fooutils  file.d > actual_struct_test.txt
diff actual_struct_test.txt expected_struct_test.txt

../../bin/dcd-client $1 -c152 -I"$PWD"/fooutils  file.d > actual_aliased_struct_test.txt
diff actual_aliased_struct_test.txt expected_aliased_struct_test.txt