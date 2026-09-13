set -e
set -u

# `foreach (item; getItems())` must infer the ELEMENT type from the call
# result: the foreach crumb previously did not unwrap the function symbol
# to its return type, so `item.` offered the array's members instead of
# Item's.
../../bin/dcd-client $1 file.d -c155 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
