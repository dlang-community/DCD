set -e
set -u

../../bin/dcd-client $1 file.d -c19 -d > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
