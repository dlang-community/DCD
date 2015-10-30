set -e
set -u

../../bin/dcd-client file.d -c16 > actual.txt
diff actual.txt expected.txt
