set -e
set -u

../../bin/dcd-client $1 file.d -d -c124 > actual.txt
diff actual.txt expected.txt
