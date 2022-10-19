set -e
set -u

../../bin/dcd-client $1 -c82 -I"$PWD"/fooutils  file.d > actual.txt
../../bin/dcd-client $1 -c97 -I"$PWD"/fooutils  file.d > actual2.txt
../../bin/dcd-client $1 -c130 -I"$PWD"/fooutils  file.d > actual3.txt
../../bin/dcd-client $1 -c176 -I"$PWD"/fooutils  file.d > actual4.txt
../../bin/dcd-client $1 -c237 -I"$PWD"/fooutils  file.d > actual5.txt
../../bin/dcd-client $1 -c311 -I"$PWD"/fooutils  file.d > actual6.txt
diff actual.txt expected.txt
diff actual2.txt expected2.txt
diff actual3.txt expected3.txt
diff actual4.txt expected4.txt
diff actual5.txt expected5.txt
diff actual6.txt expected6.txt
