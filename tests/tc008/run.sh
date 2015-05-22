set -e
set -u

dcd-client file.d -c113 > actual1.txt
diff actual1.txt expected1.txt
