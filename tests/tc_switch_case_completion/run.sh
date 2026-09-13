set -e
set -u

# `case ` at the last case label of a switch over an enum: the enum's
# members are offered, with the members already used in earlier case
# labels (red, green) filtered out.
../../bin/dcd-client $1 file.d -c170 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
