set -e
set -u

../../bin/dcd-client $1 -c133 file.d > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
