set -e
set -u

../../bin/dcd-client $1 file.d -d -c5 > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client $1 file.d -d -c61 > actual2.txt
diff actual2.txt expected2.txt

../../bin/dcd-client $1 file.d -d -c140 > actual3.txt
diff actual3.txt expected3.txt

../../bin/dcd-client $1 file.d -d -c160 > actual4.txt
diff actual4.txt expected4.txt

../../bin/dcd-client $1 file.d -d -c201 > actual5.txt
diff actual5.txt expected5.txt

../../bin/dcd-client $1 file.d -d -c208 > actual6.txt
diff actual6.txt expected6.txt

../../bin/dcd-client $1 file.d -d -c254 > actual7.txt
diff actual7.txt expected7.txt

../../bin/dcd-client $1 file.d -d -c323 > actual8.txt
diff actual8.txt expected8.txt

../../bin/dcd-client $1 file.d -d -c335 > actual8.1.txt
diff actual8.1.txt expected8.1.txt

../../bin/dcd-client $1 file.d -d -c414 > actual8.2.txt
diff actual8.2.txt expected8.2.txt

../../bin/dcd-client $1 file.d -d -c425 > actual8.3.txt
diff actual8.3.txt expected8.3.txt

../../bin/dcd-client $1 file.d -d -c457 > actual9.txt
diff actual9.txt expected9.txt

