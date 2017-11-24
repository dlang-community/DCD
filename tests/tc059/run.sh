set -e
set -u

../../bin/dcd-client $1 file.d --full -c32 > actual1.txt
diff actual1.txt expected1.txt
