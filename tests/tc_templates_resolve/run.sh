set -e
set -u

../../bin/dcd-client $1 file1.d --extended -c 831

#echo "test1"
#../../bin/dcd-client $1 file1.d --extended -c 751 > actual_1.txt
#diff actual_1.txt expected_1.txt --strip-trailing-cr


#echo "test2"
#../../bin/dcd-client $1 file2.d --extended -c 674 > actual_2.txt
#diff actual_2.txt expected_2.txt --strip-trailing-cr

