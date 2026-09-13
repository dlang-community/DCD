set -e
set -u

# UFCS completion must not suggest functions whose first parameter comes
# from a DIFFERENT instantiation of the same template: the receiver is a
# Box!"a".Handle, so fooA (Box!"a") is offered and fooB (Box!"b") is not.
../../bin/dcd-client $1 file.d -c227 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
