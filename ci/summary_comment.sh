#!/usr/bin/env bash

set -u

# Output from this script is piped to a file by CI, being run from before a
# change has been made and after a change has been made. Then both outputs are
# compared using summary_comment_diff.sh

# cd to git folder, just in case this is manually run:
ROOT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd )"
cd ${ROOT_DIR}

dub --version
ldc2 --version

# fetch missing packages before timing
dub upgrade --missing-only

rm -rf .dub bin

start=`date +%s`
dub build --build=release --config=client --compiler=ldc2 --force 2>&1 || echo "DCD BUILD FAILED"
dub build --build=release --config=server --compiler=ldc2 --force 2>&1 || echo "DCD BUILD FAILED"
end=`date +%s`
build_time=$( echo "$end - $start" | bc -l )

strip bin/dcd-server
strip bin/dcd-client

echo "STAT:statistics (-before, +after)"
echo "STAT:client size=$(wc -c bin/dcd-client)"
echo "STAT:server size=$(wc -c bin/dcd-server)"
echo "STAT:rough build time=${build_time}s"
echo "STAT:"

cd tests
./run_tests.sh --time-server --extra

echo "STAT:DCD run_tests.sh $(grep -F 'Elapsed (wall clock) time' stderr.txt)"
echo "STAT:DCD run_tests.sh $(grep -F 'Maximum resident set size (kbytes)' stderr.txt)"

echo "STAT:"
grep -E 'Request processed in .*' stderr.txt | rdmd ../ci/request_time_stats.d
echo "STAT:"

# now rebuild server with -profile=gc
cd ..
rm -rf .dub bin/dcd-server
dub build --build=profile-gc --config=server --compiler=dmd 2>&1 || echo "DCD BUILD FAILED"

cd tests
./run_tests.sh --extra

echo "STAT:top 5 GC sources in server:"
if [ ! -f "profilegc.log" ]; then
	echo 'Missing profilegc.log file!'
	echo 'Tail for stderr.txt:'
	tail -n50 stderr.txt
fi
head -n6 profilegc.log | sed 's/^/STAT:/g'
