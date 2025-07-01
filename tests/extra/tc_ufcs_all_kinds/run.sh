#!/usr/bin/env bash

if [ -z "${DC:-}" ]; then
	DC=dmd
fi

DCBASE=$(basename "${DC}")

# Set up ERROR_STYLE to make all compilers output errors in the same
# format to make matching easier in generate_tests.d.

if [[ ${DCBASE} =~ gdmd ]]; then
    ERROR_STYLE=
elif [[ ${DCBASE} =~ dmd|ldc ]]; then
    ERROR_STYLE='-verror-style=gnu -vcolumns'
else
    echo "unknonwn compiler ${DC}"
    exit 1
fi

export DC ERROR_STYLE
${DC} -run generate_tests.d "${1}"
