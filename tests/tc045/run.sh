set -e
set -u

../../bin/dcd-client $1 file.d -c26 > actual.txt # segfault if -c29 ("  XX|"), bug!
diff actual.txt expected.txt --strip-trailing-cr
