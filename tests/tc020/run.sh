set -e
set -u

../../bin/dcd-client file.d -c159 > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client file.d -c199 > actual2.txt
diff actual2.txt expected2.txt
