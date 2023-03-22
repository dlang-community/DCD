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

start=`date +%s`
dub build --build=release --config=client 2>&1 || echo "DCD BUILD FAILED"
dub build --build=release --config=server 2>&1 || echo "DCD BUILD FAILED"
end=`date +%s`
build_time=$( echo "$end - $start" | bc -l )

strip bin/dcd-server
strip bin/dcd-client

echo "STAT:statistics (-before, +after)"
echo "STAT:client size=$(wc -c bin/dcd-client)"
echo "STAT:server size=$(wc -c bin/dcd-server)"
echo "STAT:rough build time=${build_time}s"
echo "STAT:"

# now rebuild server with -profile=gc
dub build --build=profile-gc --config=server 2>&1 || echo "DCD BUILD FAILED"

cd tests
./run_tests.sh --time-server
sleep 1

echo "STAT:DCD run_tests.sh $(grep -F 'Elapsed (wall clock) time' stderr.txt)"
echo "STAT:DCD run_tests.sh $(grep -F 'Maximum resident set size (kbytes)' stderr.txt)"

echo "STAT:"
grep -E 'Request processed in .*' stderr.txt | rdmd ../ci/request_time_stats.d
echo "STAT:"
echo "STAT:top 5 GC sources in server:"
head -n6 profilegc.log | sed 's/^/STAT:/g'
