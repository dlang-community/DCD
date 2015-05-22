set -e
set -u

dcd-client file.d -c162 > actual1.txt
diff actual1.txt expected1.txt

dcd-client file.d -c173 > actual2.txt
diff actual2.txt expected2.txt

dcd-client file.d -c184 > actual3.txt
diff actual3.txt expected3.txt

dcd-client file.d -c195 > actual4.txt
diff actual4.txt expected4.txt
