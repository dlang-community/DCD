set -e
set -u

../../bin/dcd-client $1 file.d -u -c8 | sed s\""$(dirname "$(pwd)")"\"\" > actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr
