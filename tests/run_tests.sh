#! /bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
NORMAL="\033[0m"
IMPORTS=$(pwd)/imports
export IMPORTS
SOCKETMODES="unix tcp"
TIME_SERVER=0

# `--arguments` must come before test dirs!
while (( "$#" )); do
	if [[ "$1" == "--tcp-only" ]]; then
		# only test TCP sockets
		SOCKETMODES="tcp"
	elif [[ "$1" == "--unix-only" ]]; then
		# only test unix domain sockets
		SOCKETMODES="unix"
	elif [[ "$1" == "--time-server" ]]; then
		# --time-server runs dcd-server through /usr/bin/time, for statistics
		# implies `--unix-only` (since we only want a single mode to time)
		# socket mode can still be overriden with `--tcp-only`
		TIME_SERVER=1
		SOCKETMODES="unix"
	elif [[ "$1" =~ ^-- ]]; then
		echo "Unrecognized test argument: $1"
		exit 1
	else
		break
	fi

	shift
done

if [ -z "${1:-}" ];
then
	TESTCASES="tc*"
else
	TESTCASES="$1"
fi

fail_count=0
pass_count=0
client="../bin/dcd-client"
server="../bin/dcd-server"
tcp=""
server_pid=""

function startServer()
{
	if [[ "$TIME_SERVER" == "1" ]]; then
		/usr/bin/time -v "$server" "$tcp" --ignoreConfig -I $IMPORTS 2>stderr.txt > stdout.txt &
		server_pid=$!
	else
		"$server" "$tcp" --ignoreConfig -I $IMPORTS 2>stderr.txt > stdout.txt &
		server_pid=$!
	fi
	sleep 1
}

function waitShutdown()
{
	if [[ -z "$server_pid" ]]; then
		sleep 0.5 # not owned by us
	else
		( sleep 15 ; echo 'Waiting for shutdown timed out'; kill $server_pid ) &
		killerPid=$!

		wait $server_pid
		status=$?
		(kill -0 $killerPid && kill $killerPid) || true

		server_pid=""

		return $status
	fi
}

# Make sure that the server is shut down
echo "Shutting down currently-running server..."
"$client" --shutdown 2>/dev/null > /dev/null
"$client" --shutdown --tcp 2>/dev/null > /dev/null

for socket in $SOCKETMODES; do # supported: unix tcp
	# allow some time for server to shutdown
	waitShutdown

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
		sleep "${sleepTime}"
	done

	# Run tests
	for testCase in $TESTCASES; do
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

	waitShutdown

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
