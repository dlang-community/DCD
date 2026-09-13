set -e
set -u

# A slice expression receiver (`arr[1..2].`) must offer UFCS functions
# taking the array type (sliceFunc), not the element type (elemFunc).
../../bin/dcd-client $1 file.d -c174 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
