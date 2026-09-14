set -e
set -u

../../bin/dcd-client $1 file.d -c55 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
../../bin/dcd-client $1 file2.d -c51 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr
../../bin/dcd-client $1 file3.d -c68 > actual3.txt
diff actual3.txt expected3.txt --strip-trailing-cr
