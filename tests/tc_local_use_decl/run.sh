set -e
set -u

# Uses of the symbol at the cursor are found regardless of whether the
# cursor is on the declaration or on a use: the tree must be fully parsed
# (the autocomplete parser would otherwise skip blocks after the cursor).
# Cursor 35 is on the declaration of x (line 3), cursor 76 on its use
# (line 9); both must report the declaration and both uses.
../../bin/dcd-client $1 file.d -c35 --localUse > actual.txt
diff actual.txt expected.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c76 --localUse > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
