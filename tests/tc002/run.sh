set -e
set -u

../../bin/dcd-client file.d -c52 > actual.txt
diff actual.txt expected.txt
