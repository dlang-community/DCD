set -e
set -u

../../bin/dcd-client $1 file.d -c 15 | sed s\""$(dirname "${TESTCWD}")"\"\" > actual3.txt
diff actual3.txt expected3.txt --strip-trailing-cr

../../bin/dcd-client $1 -I bar.d

../../bin/dcd-client $1 file.d -c 15 | sed s\""$(dirname "${TESTCWD}")"\"\" > actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c 40 | sed s\""$(dirname "${TESTCWD}")"\"\" > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr

../../bin/dcd-client $1 -R bar.d

../../bin/dcd-client $1 file.d -c 15 | sed s\""$(dirname "${TESTCWD}")"\"\" > actual3.txt
diff actual3.txt expected3.txt --strip-trailing-cr
