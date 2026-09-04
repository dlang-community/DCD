set -e
set -u

../../bin/dcd-client $1 -c59 -I"$PWD"/inheritutils  file.d > actual_derived_class_test.txt
diff actual_derived_class_test.txt expected_derived_class_test.txt

../../bin/dcd-client $1 -c59 -I"$PWD"/inheritutils  file2.d > actual_multi_base_test.txt
diff actual_multi_base_test.txt expected_multi_base_test.txt

../../bin/dcd-client $1 -c59 -I"$PWD"/inheritutils  file3.d > actual_multilevel_test.txt
diff actual_multilevel_test.txt expected_multilevel_test.txt

../../bin/dcd-client $1 -c58 -I"$PWD"/inheritutils  file4.d > actual_ref_excluded_test.txt
diff actual_ref_excluded_test.txt expected_ref_excluded_test.txt
