set -e
set -u

../../bin/dcd-client $1 --extended file.d -c72 > actual.txt
diff actual.txt expected.txt

../../bin/dcd-client $1 --extended file_nf.d -c58 > actual_nf.txt
diff actual_nf.txt expected_nf.txt

../../bin/dcd-client $1 --extended file_crash_return_auto.d -c72 > actual_crash_return_auto.txt
diff actual_crash_return_auto.txt expected_crash_return_auto.txt
