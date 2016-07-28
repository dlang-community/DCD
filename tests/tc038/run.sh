set -e
set -u

../../bin/dcd-client $1 file.d -c70 > actual.txt
diff actual.txt expected1.txt

../../bin/dcd-client $1 file.d -c143 > actual.txt
diff actual.txt expected1.txt

../../bin/dcd-client $1 file.d -c242 > actual.txt
diff actual.txt expected2.txt
