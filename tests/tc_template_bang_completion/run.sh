set -e
set -u

../../bin/dcd-client $1 file.d -c155 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c196 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c239 > actual3.txt
diff actual3.txt expected3.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c283 > actual4.txt
diff actual4.txt expected4.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c339 > actual5.txt
diff actual5.txt expected5.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c393 > actual6.txt
diff actual6.txt expected6.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c437 > actual7.txt
diff actual7.txt expected7.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c482 > actual8.txt
diff actual8.txt expected8.txt --strip-trailing-cr
