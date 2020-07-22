#!/bin/bash

set -e

if [[ $BUILD == dub ]]; then
    if [[ -n $LIBDPARSE_VERSION ]]; then
        rdmd ./d-test-utils/test_with_package.d $LIBDPARSE_VERSION libdparse -- dub build --build=release --config=client
        rdmd ./d-test-utils/test_with_package.d $LIBDPARSE_VERSION libdparse -- dub build --build=release --config=server
    elif [[ -n $DSYMBOL_VERSION ]]; then
        rdmd ./d-test-utils/test_with_package.d $DSYMBOL_VERSION dsymbol -- dub build --build=release --config=client
        rdmd ./d-test-utils/test_with_package.d $DSYMBOL_VERSION dsymbol -- dub build --build=release --config=server
    else
        echo 'Cannot run test without LIBDPARSE_VERSION nor DSYMBOL_VERSION environment variable'
        exit 1
    fi
elif [[ $DC == ldc2 ]]; then
    git submodule update --init --recursive
    make ldc -j2
else
    git submodule update --init --recursive
    make debug -j2
fi

cd tests && ./run_tests.sh
