set -e
set -u

# `auto a = Plain.init` must infer the aggregate type: the builtin `init`
# property symbol carries no type, so the initializer walk previously
# dead-ended and `a.` offered nothing.
../../bin/dcd-client $1 file.d -c234 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
