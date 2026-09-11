set -e
set -u

# Completion right after the `import` keyword (nothing typed yet) must
# offer the available modules/packages. The server is shared across the
# whole suite and earlier tests (e.g. tc062) add their own directories
# as import paths, so the exact item set is not stable — assert on the
# entries that must be present instead of diffing the full list.
../../bin/dcd-client $1 file.d -c7 > actual.txt
grep -q "^object	M$" actual.txt
grep -q "^point	M$" actual.txt
grep -q "^std	P$" actual.txt
grep -q "^circular	P$" actual.txt
