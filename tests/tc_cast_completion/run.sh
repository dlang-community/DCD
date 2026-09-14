set -e
set -u

../../bin/dcd-client $1 file.d -c102 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
../../bin/dcd-client $1 file2.d -c69 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr
