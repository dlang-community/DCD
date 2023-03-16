set -e
set -u

echo "import: $PWD/testing"

../../bin/dcd-client $1 app.d --extended -I $PWD/ -c50 > actual.txt
echo -e "identifiers\nworld\tv\tWorld world\t$PWD/testing/a.d 77\t\tWorld" > expected.txt
diff actual.txt expected.txt --strip-trailing-cr
