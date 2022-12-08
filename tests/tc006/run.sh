set -e
set -u

../../bin/dcd-client $1 file.d -c184 > actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c199 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c216 > actual3.txt
diff actual3.txt expected3.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c231 > actual4.txt
diff actual4.txt expected4.txt --strip-trailing-cr
