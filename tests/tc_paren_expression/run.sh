set -e
set -u

../../bin/dcd-client $1 file.d -c93 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
../../bin/dcd-client $1 file2.d -c109 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr
../../bin/dcd-client $1 file3.d -c91 > actual3.txt
diff actual3.txt expected3.txt --strip-trailing-cr
../../bin/dcd-client $1 file4.d -c51 > actual4.txt
diff actual4.txt expected4.txt --strip-trailing-cr
