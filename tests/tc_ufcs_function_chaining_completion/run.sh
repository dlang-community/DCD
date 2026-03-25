set -e
set -u

../../bin/dcd-client $1 -c158 file.d > actual_completion_test.txt
diff actual_completion_test.txt expected_completion_test.txt