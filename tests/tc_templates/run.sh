set -e
set -u

../../bin/dcd-client $1 file.d -c 97  > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
