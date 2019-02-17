set -e
set -u

../../bin/dcd-client $1 file.d -c49 > actual1.txt
diff actual1.txt expected1.txt
../../bin/dcd-client $1 file.d -c103 > actual2.txt
diff actual2.txt expected2.txt
