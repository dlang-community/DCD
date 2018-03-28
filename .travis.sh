#!/bin/bash

set -e

if [[ $BUILD == dub ]]; then
    dub build --build=release --config=client
    dub build --build=release --config=server
elif [[ $DC == ldc2 ]]; then
    git submodule update --init --recursive
    make ldc -j2
else
    git submodule update --init --recursive
    make debug -j2
fi

cd tests && ./run_tests.sh
