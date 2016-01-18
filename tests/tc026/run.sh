set -e
set -u

../../bin/dcd-client file.d -c53 > actual1.txt
diff actual1.txt expected1.txt
