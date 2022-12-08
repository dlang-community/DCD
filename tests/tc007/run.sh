set -e
set -u

../../bin/dcd-client $1 file.d -c97 > actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c130 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr
