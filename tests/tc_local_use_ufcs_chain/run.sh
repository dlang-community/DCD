set -e
set -u

# Uses of a free function called with UFCS syntax on a MEMBER-CHAIN receiver
# (`ctx.vertexBuffer.cleanupGpuBuffer()`): the receiver's base identifier is
# a struct field, not a scope-level name, so the UFCS type deduction must
# resolve the chain from its first segment. Cursor 176 is inside the
# declaration (line 14), cursor 283 inside the first use (line 18), cursor
# 320 inside the second use (line 19). All three must report the
# declaration (171) and both uses (278, 315).
../../bin/dcd-client $1 file.d -c176 --localUse > actual.txt
diff actual.txt expected.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c283 --localUse > actual.txt
diff actual.txt expected.txt --strip-trailing-cr

../../bin/dcd-client $1 file.d -c320 --localUse > actual.txt
diff actual.txt expected.txt --strip-trailing-cr
