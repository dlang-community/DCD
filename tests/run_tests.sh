#! /bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
NORMAL="\033[0m"
IMPORTS=$(pwd)/imports

fail_count=0
pass_count=0

function startServer()
{
	if [[ $socket == "unix" ]]; then
		../bin/dcd-server --ignoreConfig -I $IMPORTS 2>stderr.txt > stdout.txt &
	else
		../bin/dcd-server --tcp --ignoreConfig -I $IMPORTS 2>stderr.txt > stdout.txt &
	fi
	server_pid=$!
	sleep 1s;
}

# Make sure that the server is shut down
echo "Shutting down currently-running server..."
../bin/dcd-client --shutdown 2>/dev/null > /dev/null
../bin/dcd-client --shutdown --tcp 2>/dev/null > /dev/null
sleep 1s;

for socket in unix tcp; do
	echo "Running tests for $socket sockets"

	# Start up the server
	echo "Starting server..."
	startServer

	# Run tests
	for testCase in tc*; do
		cd $testCase

		if [[ $socket == "unix" ]]; then
			./run.sh ""
		else
			./run.sh "--tcp"
		fi
		if [[ $? -eq 0 ]]; then
			echo -e "${YELLOW}$socket:$testCase:${NORMAL} ... ${GREEN}Pass${NORMAL}";
			let pass_count=pass_count+1
		else
			echo -e "${YELLOW}$socket:$testCase:${NORMAL} ... ${RED}Fail${NORMAL}";
			let fail_count=fail_count+1
		fi

		cd - > /dev/null;

		if ! kill -0 $server_pid > /dev/null 2>&1; then
			echo "Server no longer running."
			echo -e "${RED}STDERR:${NORMAL}"
			cat stderr.txt
			echo -e "${RED}STDOUT:${NORMAL}"
			cat stdout.txt

			echo "Restarting server..."
			startServer
		fi
	done

	# Shut down
	echo "Shutting down server..."
	if [[ $socket == "unix" ]]; then
		../bin/dcd-client --shutdown 2>/dev/null > /dev/null
	else
		../bin/dcd-client --shutdown --tcp 2>/dev/null > /dev/null
	fi

	# Report
	if [[ $fail_count -eq 0 ]]; then
		echo -e "${GREEN}${pass_count} tests passed and ${fail_count} failed.${NORMAL}"
	else
		echo -e "${RED}${pass_count} tests passed and ${fail_count} failed.${NORMAL}"
		echo -e "${RED}STDERR:${NORMAL}"
		cat stderr.txt
		echo -e "${RED}STDOUT:${NORMAL}"
		cat stdout.txt
		exit 1
	fi
done

