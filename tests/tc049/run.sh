set -e
set -u

../../bin/dcd-client $1 file.d -l -c76 > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client $1 file.d -l -c47 > actual2.txt
diff actual2.txt expected2.txt

../../bin/dcd-client $1 file.d -l -c218 > actual3.txt
diff actual3.txt expected3.txt
