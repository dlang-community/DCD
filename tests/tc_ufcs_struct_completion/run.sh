set -e
set -u

../../bin/dcd-client $1 -c82 -I"$PWD"/fooutils  file.d > actual_struct_test.txt
diff actual_struct_test.txt expected_struct_test.txt

../../bin/dcd-client $1 -c157 -I"$PWD"/fooutils  file.d > actual_aliased_struct_test.txt
diff actual_aliased_struct_test.txt expected_aliased_struct_test.txt

../../bin/dcd-client $1 -c161 -I"$PWD"/fooutils  file.d > actual_should_not_complete_test.txt
diff actual_should_not_complete_test.txt expected_should_not_complete_test.txt

../../bin/dcd-client $1 -c165 -I"$PWD"/fooutils  file.d > actual_should_not_complete_test2.txt
diff actual_should_not_complete_test2.txt expected_should_not_complete_test2.txt