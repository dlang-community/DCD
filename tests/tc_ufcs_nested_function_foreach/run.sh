set -e
set -u

../../bin/dcd-client $1 file.d -c155 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
