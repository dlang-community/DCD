set -e
set -u

cp testfile1_old.d ../imports/testfile1.d
# Sleep because modification times aren't stored with granularity of less
# than one second
sleep 1s;

dcd-client file.d -c84 > actual1.txt
diff actual1.txt expected1.txt

cp testfile1_new.d ../imports/testfile1.d
# Same here
sleep 1s;

dcd-client file.d -c84 > actual2.txt
diff actual2.txt expected2.txt
