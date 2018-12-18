set -e
set -u

../../bin/dcd-client $1 file.d -c59 > actual.txt
diff actual.txt expected.txt
