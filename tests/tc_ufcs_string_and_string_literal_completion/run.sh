set -e
set -u

#TEST CASE 0
SOURCE_FILE_0=file.d
ACTUAL_FILE_NAME_0=actual_string_literal_test.txt
EXPECTED_FILE_NAME_0=expected_string_literal_test.txt

../../bin/dcd-client $1 -c99 $SOURCE_FILE_0 > $ACTUAL_FILE_NAME_0
diff $ACTUAL_FILE_NAME_0 $EXPECTED_FILE_NAME_0 --strip-trailing-cr

ACTUAL_FILE_NAME_1=actual_string_test.txt
EXPECTED_FILE_NAME_1=expected_string_test.txt
../../bin/dcd-client $1 -c103 $SOURCE_FILE_0 > $ACTUAL_FILE_NAME_1
diff $ACTUAL_FILE_NAME_1 $EXPECTED_FILE_NAME_1 --strip-trailing-cr