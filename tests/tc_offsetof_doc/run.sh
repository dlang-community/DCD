set -e
set -u

../../bin/dcd-client $1 --doc file.d -c163 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
