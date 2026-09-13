set -e
set -u

# `case gr` in a final switch over an enum: the enum's members are
# offered filtered by the partial, with used members (red) excluded.
../../bin/dcd-client $1 file.d -c214 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
