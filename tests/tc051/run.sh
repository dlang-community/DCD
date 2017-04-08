set -e
set -u

../../bin/dcd-client $1 file.d -c29 > actual.txt
diff actual.txt expected.txt

../../bin/dcd-client $1 file1.d -c25 > actual1.txt
diff actual1.txt expected1.txt
