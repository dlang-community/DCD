set -e
set -u

# A partial identifier at a statement start offers the matching statement
# keywords (assert) and local declaration keywords (enum) alongside the
# scope symbols (assertHelper).
../../bin/dcd-client $1 file.d -c90 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
../../bin/dcd-client $1 file.d -c108 > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr
