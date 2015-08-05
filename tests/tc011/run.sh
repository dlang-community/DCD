set -e
set -u

dcd-client file.d -c48 > actual1.txt
diff actual1.txt expected1.txt
