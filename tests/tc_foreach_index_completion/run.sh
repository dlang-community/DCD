set -e
set -u

# The index variable of `foreach (i, item; items)` must resolve (to
# size_t): previously only the LAST loop variable got a symbol, so `i.`
# offered nothing.
../../bin/dcd-client $1 file.d -c135 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
