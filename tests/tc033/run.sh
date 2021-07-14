set -e
set -u

../../bin/dcd-client $1 file.d -u -c22 | sed s\""$(dirname "$(pwd)")"\"\" > actual1.txt
diff actual1.txt expected1.txt

# should work on last character of identifier
../../bin/dcd-client $1 file.d -u -c24 | sed s\""$(dirname "$(pwd)")"\"\" > actual2.txt
diff actual2.txt expected1.txt
