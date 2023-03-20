set -e
set -u

../../bin/dcd-client $1 -c266 file.d > actual_array_test.txt
diff actual_array_test.txt expected_array_test.txt