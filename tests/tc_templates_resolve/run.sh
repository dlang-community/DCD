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
check file1 280 actual_1_1 expected_1_1


#echo "test2"
check file1 315 actual_1_2 expected_1_2


#echo "test3"
check file2 268 actual_2_1 expected_2_1


#echo "test4"
check file2 305 actual_2_2 expected_2_2


#echo "test5"
check file3 195 actual_3_1 expected_3_1


#echo "test6"
check file3 246 actual_3_2 expected_3_2


#echo "test7"
check file3 274 actual_3_3 expected_3_3


#echo "test8"
check file3 328 actual_3_4 expected_3_4


#echo "test9"
check file3 433 actual_3_5 expected_3_5


#echo "test complex"
check complex 1121 actual_complex_1 expected_complex_1
check complex 1162 actual_complex_2 expected_complex_2
check complex 1205 actual_complex_3 expected_complex_3
check complex 1248 actual_complex_4 expected_complex_4
check complex 1271 actual_complex_5 expected_complex_5
check complex 1296 actual_complex_6 expected_complex_6
check complex 1321 actual_complex_7 expected_complex_7
check complex 1345 actual_complex_8 expected_complex_8
