set -e
set -u

../../bin/dcd-client $1 file.d --extended -c$(stat -c %s file.d) > actual1.txt
diff actual1.txt expected1.txt
