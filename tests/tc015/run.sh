set -e
set -u

../../bin/dcd-client file1.d -c84 > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client file2.d -c73 > actual2.txt
diff actual2.txt expected2.txt
