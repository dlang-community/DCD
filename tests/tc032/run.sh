set -e
set -u

../../bin/dcd-client $1 file.d -l -c 15 > actual1.txt
printf "$(dirname "${TESTCWD}")/imports${SLASHSLASH}std${SLASHSLASH}stdio.d\t0\n" > expected1.txt
diff actual1.txt expected1.txt --strip-trailing-cr
