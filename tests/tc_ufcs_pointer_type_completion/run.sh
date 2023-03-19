set -e
set -u

../../bin/dcd-client $1 -c247 file.d > actual_pointer_test.txt
diff actual_pointer_test.txt expected_pointer_test.txt