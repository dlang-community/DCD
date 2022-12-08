set -e
set -u

cp testfile1_old.d ../imports/testfile1.d
# Sleep because modification times aren't stored with granularity of less
# than one second
sleep 1

../../bin/dcd-client $1 file.d -c84 > actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr

cp testfile1_new.d ../imports/testfile1.d
# Same here
sleep 1

../../bin/dcd-client $1 file.d -c84 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr
