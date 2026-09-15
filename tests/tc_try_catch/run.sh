set -e
set -u

# The catch parameter must become a symbol in the catch body's scope with
# the caught type (`e.` offers Error's members), the body must still see
# locals declared inside it, and an unnamed catch parameter (`catch (Error)`)
# must not break the body's scope either.
../../bin/dcd-client $1 file.d -c133 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
../../bin/dcd-client $1 file.d -c105 > actual.txt
diff actual.txt expected2.txt --strip-trailing-cr
../../bin/dcd-client $1 file.d -c216 > actual.txt
diff actual.txt expected2.txt --strip-trailing-cr
../../bin/dcd-client $1 file.d -c301 > actual.txt
diff actual.txt expected2.txt --strip-trailing-cr
