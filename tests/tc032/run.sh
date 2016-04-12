set -e
set -u

../../bin/dcd-client $1 file.d -l -c 15 | sed s\""$(dirname "$(pwd)")"\"\" > actual1.txt
diff actual1.txt expected1.txt
