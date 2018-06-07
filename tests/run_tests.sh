#! /bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
NORMAL="\033[0m"
IMPORTS=$(pwd)/imports

fail_count=0
pass_count=0
client="../bin/dcd-client"
server="../bin/dcd-server"
tcp=""

function startServer()
{
	"$server" "$tcp" --ignoreConfig -I $IMPORTS 2>stderr.txt > stdout.txt &
	server_pid=$!
	sleep 1s;
}

# Make sure that the server is shut down
echo "Shutting down currently-running server..."
"$client" --shutdown 2>/dev/null > /dev/null
"$client" --shutdown --tcp 2>/dev/null > /dev/null

for socket in unix tcp; do
	# allow some time for server to shutdown
	sleep 0.5s;

	if [[ $socket == "tcp" ]]; then
		tcp="--tcp"
	else
		tcp=""
	fi

	echo "Running tests for $socket sockets"

	# Start up the server
	echo "Starting server..."
	startServer

	# make sure the server is up and running
	for i in {0..4} ; do
		if "$client" "$tcp" --status | grep "Server is running" ; then
			break;
		fi
		sleepTime=$((1 << $i))
		echo "Server isn't up yet. Sleeping for ${sleepTime}s"
		sleep "${sleepTime}s"
	done

	# Run tests
	for testCase in tc*; do
		cd $testCase

		./run.sh "$tcp"
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
	"$client" --shutdown "$tcp" 2>/dev/null > /dev/null

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
