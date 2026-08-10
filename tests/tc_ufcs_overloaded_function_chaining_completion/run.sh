set -e
set -u

../../bin/dcd-client $1 --extended -c288 file.d > actual_completion_test.txt
diff actual_completion_test.txt expected_completion_test.txt --strip-trailing-cr

../../bin/dcd-client $1 --extended -c511 file.d > actual_completion_test2.txt
diff actual_completion_test2.txt expected_completion_test2.txt --strip-trailing-cr