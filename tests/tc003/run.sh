set -e
set -u

dcd-client file.d -c863 > actual.txt
diff actual.txt expected.txt
