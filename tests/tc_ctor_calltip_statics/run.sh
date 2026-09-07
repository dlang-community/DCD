set -e
set -u

# Cursor offsets are computed from the current file contents so the test
# survives tools that prepend a module declaration to the test files.
POS1=$(python3 -c "
with open('file.d') as f: c = f.read()
print(c.rindex('MyStruct(') + len('MyStruct('))")
POS2=$(python3 -c "
with open('file.d') as f: c = f.read()
print(c.rindex('Versioned(') + len('Versioned('))")

../../bin/dcd-client $1 file.d -c$POS1 > actual.txt
diff actual.txt expected.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c$POS2 > actual.txt
diff actual.txt expected2.txt --strip-trailing-cr
