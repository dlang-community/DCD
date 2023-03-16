set -e
set -u

../../bin/dcd-client $1 file.d --extended -I"$PWD"/newpackage -c$(wc -c < file.d) > actual1.txt
echo -e "identifiers\nSomeStruct\ts\t\t$PWD/newpackage/newmodule.d 26\t\t" > expected1.txt
diff actual1.txt expected1.txt --strip-trailing-cr
