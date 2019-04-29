set -e
set -u

rm -f actual1.txt actual2.txt actual3.txt actual0.txt

../../bin/dcd-client $1 file1.d -c 137 | sed s\""$(dirname "$(pwd)")"\"\" > actual0.txt
diff actual0.txt expected0.txt

../../bin/dcd-client $1 -I bar.d

../../bin/dcd-client $1 file1.d -c 137 | sed s\""$(dirname "$(pwd)")"\"\" > actual1.txt
diff actual1.txt expected1.txt

../../bin/dcd-client $1 file1.d -c 152 | sed s\""$(dirname "$(pwd)")"\"\" > actual1_1.txt
diff actual1_1.txt expected1_1.txt

../../bin/dcd-client $1 file1.d -c 170 | sed s\""$(dirname "$(pwd)")"\"\" > actual2.txt
diff actual2.txt expected2.txt

../../bin/dcd-client $1 file2.d -c 83 | sed s\""$(dirname "$(pwd)")"\"\" > actual3.txt
diff actual3.txt expected3.txt

../../bin/dcd-client $1 -R bar.d

../../bin/dcd-client $1 file1.d -c 137 | sed s\""$(dirname "$(pwd)")"\"\" > actual0.txt
diff actual0.txt expected0.txt
