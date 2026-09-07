set -e
set -u

# Cursor offsets are computed from the current file contents so the test
# survives tools that prepend a module declaration to the test files.
POS1=$(python3 -c "
with open('file1.d') as f: c = f.read()
print(c.rindex('VkDev') + len('VkDev'))")
POS2=$(python3 -c "
with open('file2.d') as f: c = f.read()
print(c.rindex('MyType') + 1)")
../../bin/dcd-client $1 file1.d -c$POS1 > actual1.txt
diff actual1.txt expected1.txt --strip-trailing-cr

../../bin/dcd-client $1 file2.d -c$POS2 --symbolLocation > actual2.txt
diff actual2.txt expected2.txt --strip-trailing-cr
