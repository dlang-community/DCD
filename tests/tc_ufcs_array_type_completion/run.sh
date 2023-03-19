set -e
set -u

../../bin/dcd-client $1 -c259 file.d > actual_array_test.txt
diff actual_array_test.txt expected_array_test.txt