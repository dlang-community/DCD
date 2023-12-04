set -e
set -u

../../bin/dcd-client $1 --inlayHints file.d > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
