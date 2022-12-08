set -e
set -u

../../bin/dcd-client $1 file.d -c12 -d > actual.txt
diff actual.txt expected.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c35 -d > actual.txt
diff actual.txt expected.txt --strip-trailing-cr