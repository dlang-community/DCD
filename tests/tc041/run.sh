set -e
set -u

../../bin/dcd-client $1 file.d -d -c161 > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client $1 file.d -d -c170 > actual2.txt
diff actual2.txt expected2.txt

../../bin/dcd-client $1 file.d -d -c178 > actual3.txt
diff actual3.txt expected3.txt

../../bin/dcd-client $1 file.d -d -c187 > actual4.txt
diff actual4.txt expected4.txt

