set -e
set -u

../../bin/dcd-client $1 file.d -x -c58 > actual1.txt
../../bin/dcd-client $1 file.d -x -c108 >> actual1.txt
../../bin/dcd-client $1 file.d -x -c165 >> actual1.txt
../../bin/dcd-client $1 file.d -x -c226 >> actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr
