set -e
set -u

../../bin/dcd-client $1 -I "$(pwd)"
echo | ../../bin/dcd-client $1 --search funcName > actual1.txt
printf "${TESTCWD}${SLASHSLASH}file.d\tf\t5\n" > expected1.txt
diff actual1.txt expected1.txt --strip-trailing-cr
