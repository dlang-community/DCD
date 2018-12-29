set -e
set -u

../../bin/dcd-client $1 file.d -c37 > actual.txt
diff actual.txt expected.txt
