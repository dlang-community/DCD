set -e
set -u

../../bin/dcd-client $1 file.d -c113 > actual1.txt
diff actual1.txt expected1.txt
