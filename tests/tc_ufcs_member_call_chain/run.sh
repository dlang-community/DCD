set -e
set -u

# A member-call chain receiver (`f.make().`): the call result of a METHOD
# must become the receiver, so UFCS functions taking the method's return
# type (Item) are offered. Currently failing: the receiver deduces as the
# method symbol itself, so nothing matches.
../../bin/dcd-client $1 file.d -c202 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
