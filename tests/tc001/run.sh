set -e
set -u

dcd-client file.d -c12 > actual.txt
diff actual.txt expected.txt
