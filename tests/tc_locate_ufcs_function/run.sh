set -e
set -u

../../bin/dcd-client $1 -c57 -l -I"$PWD"/barutils file.d > actual.txt
printf "${TESTCWD}/barutils${SLASHSLASH}barutils.d\t22\n" > expected.txt
diff actual.txt expected.txt --strip-trailing-cr
