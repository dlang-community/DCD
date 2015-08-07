set -e
set -u

dcd-client file.d -c162 > actual1.txt
diff actual1.txt expected1.txt
