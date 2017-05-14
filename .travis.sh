#!/bin/bash

set -e

if [[ $BUILD == dub ]]; then
    mkdir bin

    dub build --build=release --config=client
    dub build --build=release --config=server

    mv dcd-client ./bin
    mv dcd-server ./bin
elif [[ $DC == ldc2 ]]; then
    git submodule update --init --recursive
    make ldc -j2
else
    git submodule update --init --recursive
    make debug -j2
fi

cd tests && ./run_tests.sh
