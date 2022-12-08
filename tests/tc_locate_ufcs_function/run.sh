set -e
set -u

../../bin/dcd-client $1 -c57 -l -I"$PWD"/barutils file.d > actual.txt
echo -e "$PWD/barutils/barutils.d\t22" > expected.txt
diff actual.txt expected.txt --strip-trailing-cr
