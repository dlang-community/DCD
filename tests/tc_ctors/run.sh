set -e
set -u

../../bin/dcd-client $1 file.d -c122 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c162 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
