#! /bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
NORMAL="\033[0m"
IMPORTS=$(pwd)/imports

fail_count=0
pass_count=0

# Make sure that the server is shut down
echo "Shutting down currently-running server..."
../bin/dcd-client --shutdown 2>/dev/null > /dev/null
sleep 1s;

# Start up the server
echo "Starting server..."
../bin/dcd-server --ignoreConfig -I $IMPORTS 2>stderr.txt > stdout.txt &
sleep 1s;

# Run tests
for testCase in tc*; do
	cd $testCase;

	./run.sh;
	if [ $? -eq 0 ]; then
		echo -e "${YELLOW}$testCase:${NORMAL} ... ${GREEN}Pass${NORMAL}";
		let pass_count=pass_count+1
	else
		echo -e "${YELLOW}$testCase:${NORMAL} ... ${RED}Fail${NORMAL}";
		let fail_count=fail_count+1
	fi

	cd - > /dev/null;
done

# Shut down
echo "Shutting down server..."
../bin/dcd-client --shutdown 2>/dev/null > /dev/null

# Report
if [ $fail_count -eq 0 ]; then
	echo -e "${GREEN}${pass_count} tests passed and ${fail_count} failed.${NORMAL}"
else
	echo -e "${RED}${pass_count} tests passed and ${fail_count} failed.${NORMAL}"
	echo -e "${RED}STDERR:${NORMAL}"
	cat stderr.txt
	echo -e "${RED}STDOUT:${NORMAL}"
	cat stdout.txt
	exit 1
fi
