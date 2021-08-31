set -e
set -u

../../bin/dcd-client $1 --extended file.d -c72 > actual.txt
diff actual.txt expected.txt
