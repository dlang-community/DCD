set -e
set -u

../../bin/dcd-client $1 -c265 file.d > actual_completion_test.txt
diff actual_completion_test.txt expected_completion_test.txt --strip-trailing-cr

../../bin/dcd-client $1 -c325 file.d > actual_completion_test2.txt
diff actual_completion_test2.txt expected_completion_test2.txt --strip-trailing-cr

../../bin/dcd-client $1 -c388 file.d > actual_completion_test3.txt
diff actual_completion_test3.txt expected_completion_test3.txt --strip-trailing-cr

../../bin/dcd-client $1 -c454 file.d > actual_completion_test4.txt
diff actual_completion_test4.txt expected_completion_test4.txt --strip-trailing-cr

../../bin/dcd-client $1 -c486 file.d > actual_completion_test5.txt
diff actual_completion_test5.txt expected_completion_test5.txt --strip-trailing-cr