set -e
set -u

../../bin/dcd-client $1 -c293 file.d > actual.txt
diff actual.txt expected.txt
