set -e
set -u

../../bin/dcd-client $1 file.d -c61 > actual.txt
diff actual.txt expected.txt
