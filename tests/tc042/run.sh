set -e
set -u

../../bin/dcd-client $1 file.d -d -c21 > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client $1 file.d -d -c119 > actual2.txt
diff actual2.txt expected2.txt
