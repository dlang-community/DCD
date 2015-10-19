set -e
set -u

../../bin/dcd-client file.d -c1 > actual.txt
diff actual.txt expected.txt
