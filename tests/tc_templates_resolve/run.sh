#!/bin/bash

set -e
set -u

MODE=$1

function check () {
    echo "$1 $2"
    ../../bin/dcd-client $MODE $1.d --extended -c $2 > $3.txt
    diff $3.txt $4.txt --strip-trailing-cr
}


#echo "test1"
../../bin/dcd-client $1 file1.d --extended -c 280 > actual_1_1.txt
diff actual_1_1.txt expected_1_1.txt --strip-trailing-cr


#echo "test2"
../../bin/dcd-client $1 file1.d --extended -c 315 > actual_1_2.txt
diff actual_1_2.txt expected_1_2.txt --strip-trailing-cr



#echo "test3"
../../bin/dcd-client $1 file2.d --extended -c 268 > actual_2_1.txt
diff actual_2_1.txt expected_2_1.txt --strip-trailing-cr


#echo "test4"
../../bin/dcd-client $1 file2.d --extended -c 305 > actual_2_2.txt
diff actual_2_2.txt expected_2_2.txt --strip-trailing-cr


#echo "test5"
../../bin/dcd-client $1 file3.d --extended -c 135 > actual_3_1.txt
diff actual_3_1.txt expected_3_1.txt --strip-trailing-cr


#echo "test complex"
check complex 1121 actual_complex_1 expected_complex_1
check complex 1162 actual_complex_2 expected_complex_2
check complex 1205 actual_complex_3 expected_complex_3
check complex 1248 actual_complex_4 expected_complex_4
check complex 1271 actual_complex_5 expected_complex_5
check complex 1296 actual_complex_6 expected_complex_6
check complex 1321 actual_complex_7 expected_complex_7
check complex 1345 actual_complex_8 expected_complex_8
