set -e
set -u

../../bin/dcd-client $1 file.d -c286 -d > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client $1 file.d -c290 -d > actual2.txt
diff actual2.txt expected2.txt

../../bin/dcd-client $1 file.d -c294 -d > actual3.txt
diff actual3.txt expected3.txt

../../bin/dcd-client $1 file.d -c298 -d> actual4.txt
diff actual4.txt expected4.txt

../../bin/dcd-client $1 file.d -c302 -d> actual5.txt
diff actual5.txt expected5.txt

../../bin/dcd-client $1 file.d -c306 -d> actual6.txt
diff actual6.txt expected6.txt

../../bin/dcd-client $1 file.d -c313 -d> actual7.txt
diff actual7.txt expected7.txt
