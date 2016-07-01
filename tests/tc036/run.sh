set -e
set -u

../../bin/dcd-client $1 -I bar.d

../../bin/dcd-client $1 file.d -c 15 | sed s\""$(dirname "$(pwd)")"\"\" > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client $1 file.d -c 40 | sed s\""$(dirname "$(pwd)")"\"\" > actual2.txt
diff actual2.txt expected2.txt
