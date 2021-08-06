set -e
set -u


../../bin/dcd-client $1 file.d -c 60 > actual.txt

diff actual.txt expected.txt