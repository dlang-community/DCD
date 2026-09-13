set -e
set -u

../../bin/dcd-client $1 file.d -c165 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
