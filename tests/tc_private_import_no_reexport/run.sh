set -e
set -u

# NOTE: the module names are deliberately unique (privreexp) the suite's
# server is shared and module names collide across test directories.
../../bin/dcd-client $1 -I $PWD app.d -c44 > actual.txt
[ ! -s actual.txt ] || { cat actual.txt; exit 1; }

# The mirror case: making the links public re-exports the symbols.
sed -i.bak "s/^import privreexp.a;/public import privreexp.a;/" privreexp/package.d
sed -i.bak "s/^import privreexp.b;/public import privreexp.b;/" privreexp/a.d
trap "mv privreexp/package.d.bak privreexp/package.d; mv privreexp/a.d.bak privreexp/a.d" EXIT
../../bin/dcd-client $1 -I $PWD app.d -c44 > actual.txt
printf "identifiers\nfield\tv\n" > expected.txt
diff actual.txt expected.txt --strip-trailing-cr
