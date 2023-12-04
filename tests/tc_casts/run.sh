set -e
set -u

../../bin/dcd-client $1 file.d -c159 > actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c239 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c320 > actual3.txt
diff actual3.txt expected1.txt --strip-trailing-cr
