set -e
set -u

../../bin/dcd-client $1 file.d -c155 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c196 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c239 > actual3.txt
diff actual3.txt expected3.txt --strip-trailing-cr
