set -e
set -u

../../bin/dcd-client $1 test1.d -x -c213 > actual1.txt
../../bin/dcd-client $1 test1.d -x -c239 >> actual1.txt
../../bin/dcd-client $1 test1.d -x -c254 >> actual1.txt
../../bin/dcd-client $1 test1.d -x -c265 >> actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr

../../bin/dcd-client $1 test2.d -x -c132 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr

../../bin/dcd-client $1 test3.d -x -c83 > actual3.txt
diff actual3.txt expected3.txt --strip-trailing-cr
