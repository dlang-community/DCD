#!/usr/bin/env bash

if [ -z "${DC:-}" ]; then
	DC=dmd
fi

DC="$DC" "$DC" -run generate_tests.d "$1"
