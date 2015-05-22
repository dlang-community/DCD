set -e
set -u

dcd-client file.d -c13 > actual.txt
diff actual.txt expected.txt
