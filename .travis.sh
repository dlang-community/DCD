#!/bin/bash

set -e

make

cd tests && ./run_tests.sh
