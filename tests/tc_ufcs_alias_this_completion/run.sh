set -e
set -u

#TEST CASE 0
SOURCE_FILE_0=alias_this_on_function.d
ACTUAL_FILE_NAME_0="actual_alias_this_on_function_test.txt"
EXPECTED_FILE_NAME_0="expected_alias_this_on_function_test.txt"

../../bin/dcd-client $1 -c152 $SOURCE_FILE_0 > $ACTUAL_FILE_NAME_0
diff $ACTUAL_FILE_NAME_0 $EXPECTED_FILE_NAME_0 --strip-trailing-cr

#TEST CASE 1
SOURCE_FILE_1=plenty_alias_this_defined.d
ACTUAL_FILE_NAME_1="actual_plenty_alias_this_defined_test.txt"
EXPECTED_FILE_NAME_1="expected_plenty_alias_this_defined_test.txt"

../../bin/dcd-client $1 -c305 $SOURCE_FILE_1 > $ACTUAL_FILE_NAME_1
diff $ACTUAL_FILE_NAME_1 $EXPECTED_FILE_NAME_1 --strip-trailing-cr

#TEST CASE 2
ACTUAL_FILE_NAME_2="actual_plenty_alias_this_defined_test2.txt"
EXPECTED_FILE_NAME_2="expected_plenty_alias_this_defined_test2.txt"

../../bin/dcd-client $1 -c363 $SOURCE_FILE_1 > $ACTUAL_FILE_NAME_2
diff $ACTUAL_FILE_NAME_2 $EXPECTED_FILE_NAME_2 --strip-trailing-cr