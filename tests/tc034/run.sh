set -e
set -u

../../bin/dcd-client $1 file.d -u -c1 > actual1.txt
printf "$(dirname "${TESTCWD}")/imports${SLASHSLASH}object.d\t22\n0\n12\n" > expected1.txt
diff actual1.txt expected1.txt --strip-trailing-cr
