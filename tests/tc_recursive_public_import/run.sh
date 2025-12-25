set -e
set -u

echo "import: $PWD/testing"

../../bin/dcd-client $1 app.d --extended -I $PWD/ -c50 > actual.txt
printf "identifiers\nworld\tv\tWorld world\t${TESTCWD}/testing${SLASHSLASH}a.d 77\t\tWorld\n" > expected.txt
diff actual.txt expected.txt --strip-trailing-cr
