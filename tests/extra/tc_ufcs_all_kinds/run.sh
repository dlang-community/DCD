#!/usr/bin/env bash

if [ -z "${DC:-}" ]; then
	DC=dmd
fi

DCBASE=$(basename ${DC})

# Set up ERROR_FLAGS to make all compilers output errors in the same
# format to make matching easier in generate_tests.d. Also make them
# output all errors.
if [[ ${DCBASE} == *gdc* ]]; then
	outputFlag=-o
	# Not needed as gdc defaults to printing all errors
	ERROR_FLAGS=
elif [[ ${DCBASE} == *gdmd* ]]; then
	outputFlag=-of
	ERROR_FLAGS=
elif [[ ${DCBASE} == *ldc* || ${DCBASE} == *dmd* ]]; then
	outputFlag=-of
	ERROR_FLAGS='-verrors=0 -verror-style=gnu -vcolumns'
else
	echo "Unknown compiler ${DC}"
	exit 1
fi

$DC ${outputFlag}generate_tests generate_tests.d
export DC ERROR_FLAGS
./generate_tests "${1}"
