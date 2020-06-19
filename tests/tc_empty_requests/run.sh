set -e
set -u

../../bin/dcd-client $1 -s foo < /dev/null
../../bin/dcd-client $1 -c 1 < /dev/null
../../bin/dcd-client $1 -d -c 1 < /dev/null
../../bin/dcd-client $1 -u -c 1 < /dev/null
