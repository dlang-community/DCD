set -e
set -u

../../bin/dcd-client file.d -c33 > actual.txt
diff actual.txt expected.txt
