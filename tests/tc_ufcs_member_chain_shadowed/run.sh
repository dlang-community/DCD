set -e
set -u

# A member-chain receiver (`ctx.arr.`) must resolve through the chain even
# when the last segment (`arr`) is shadowed by a same-named local: the
# shadowing local would otherwise be picked as the base and the chain's
# own dot re-processed as a UFCS link, aborting the deduction.
../../bin/dcd-client $1 file.d -c188 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
