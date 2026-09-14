set -e
set -u

../../bin/dcd-client $1 file.d -c55 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
../../bin/dcd-client $1 file2.d -c51 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr
../../bin/dcd-client $1 file3.d -c68 > actual3.txt
diff actual3.txt expected3.txt --strip-trailing-cr
../../bin/dcd-client $1 file4.d -c34 > actual4.txt
diff actual4.txt expected4.txt --strip-trailing-cr
../../bin/dcd-client $1 file5.d -c63 > actual5.txt
diff actual5.txt expected5.txt --strip-trailing-cr
../../bin/dcd-client $1 file6.d -c53 > actual6.txt
diff actual6.txt expected6.txt --strip-trailing-cr
../../bin/dcd-client $1 file7.d -c68 > actual7.txt
diff actual7.txt expected7.txt --strip-trailing-cr
../../bin/dcd-client $1 file8.d -c69 > actual8.txt
diff actual8.txt expected8.txt --strip-trailing-cr
