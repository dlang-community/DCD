set -e
set -u

../../bin/dcd-client $1 file.d --extended -c154 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
