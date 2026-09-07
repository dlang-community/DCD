set -e
set -u

# Uses of a free function called with UFCS syntax (`foo.ufcsBar(...)`)
# must be found from both the declaration and the use, like any other
# symbol: cursor 82 is inside the declaration of ufcsBar (line 3),
# cursor 163 inside its UFCS use (line 10). Both must report the
# declaration (80) and the use (161).
../../bin/dcd-client $1 file.d -c82 --localUse > actual.txt
diff actual.txt expected.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c163 --localUse > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
