set -e
set -u

../../bin/dcd-client $1 -c163 file.d > actual.txt
diff actual.txt expected.txt
