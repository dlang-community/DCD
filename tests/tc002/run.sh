set -e
set -u

dcd-client file.d -c52 > actual.txt
diff actual.txt expected.txt
