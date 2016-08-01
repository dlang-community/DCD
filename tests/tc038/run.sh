set -e
set -u

../../bin/dcd-client $1 implicit_array.d -c108 > actual.txt
diff actual.txt expected1.txt

../../bin/dcd-client $1 excplicit_array.d -c98 > actual.txt
diff actual.txt expected1.txt

../../bin/dcd-client $1 implicit_var.d -c108 > actual.txt
diff actual.txt expected1.txt
