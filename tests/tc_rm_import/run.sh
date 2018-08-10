set -e
set -u

../../bin/dcd-client $1 file.d -c13 > actual1.txt
diff actual1.txt expected1.txt
../../bin/dcd-client $1 file.d -R$IMPORTS
../../bin/dcd-client $1 file.d -c13 > actual2.txt
diff actual2.txt expected2.txt
../../bin/dcd-client $1 -I$IMPORTS
../../bin/dcd-client $1 file.d -c13 > actual1.txt
diff actual1.txt expected1.txt
