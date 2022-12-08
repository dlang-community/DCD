set -e
set -u

../../bin/dcd-client $1 file.d --extended -c$(wc -c < file.d) > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
