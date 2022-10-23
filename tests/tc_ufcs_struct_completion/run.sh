set -e
set -u

../../bin/dcd-client $1 -c100 -I"$PWD"/fooutils  file.d > actual.txt
diff actual.txt expected.txt