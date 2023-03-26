set -e
set -u

../../bin/dcd-client $1 -c127 file.d > actual_string_literal_test.txt
diff actual_string_literal_test.txt expected_string_literal_test.txt --strip-trailing-cr

../../bin/dcd-client $1 -c131 file.d > actual_string_test.txt
diff actual_string_test.txt expected_string_test.txt --strip-trailing-cr