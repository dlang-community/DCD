set -e
set -u

../../bin/dcd-client --serverState > actual1.txt
diff actual1.txt expected1.txt
