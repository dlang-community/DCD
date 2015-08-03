set -e
set -u

dcd-client file.d -c83 > actual1.txt
diff actual1.txt expected1.txt

dcd-client file.d -c93 > actual2.txt
diff actual2.txt expected2.txt

dcd-client file.d -c148 > actual3.txt
diff actual3.txt expected3.txt
