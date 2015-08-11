set -e
set -u

../../bin/dcd-client file.d -c187 > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client file.d -c211 > actual2.txt
diff actual2.txt expected2.txt
