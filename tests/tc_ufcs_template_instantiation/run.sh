set -e
set -u

# UFCS completion must not suggest functions whose first parameter comes
# from a DIFFERENT instantiation of the same template: the receiver is a
# Box!"a".Handle, so fooA (Box!"a") is offered and fooB (Box!"b") is not.
# The alias forms (BoxA/BoxB) must behave identically: an alias of an
# instantiation keeps its identity, both for member chains (BoxA.Handle)
# and bare alias parameters.
../../bin/dcd-client $1 file.d -c394 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
