set -e
set -u

../../bin/dcd-client file.d -c13 > actual.txt
diff actual.txt expected.txt
