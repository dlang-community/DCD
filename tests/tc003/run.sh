set -e
set -u

dcd-client file.d -c839 > actual1.txt
diff actual1.txt expected1.txt

dcd-client file.d -c862 > actual2.txt
diff actual2.txt expected2.txt
