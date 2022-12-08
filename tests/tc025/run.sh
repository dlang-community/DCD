set -e
set -u

../../bin/dcd-client $1 file.d -c94 > actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr
