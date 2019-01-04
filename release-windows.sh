#!/usr/bin/env bash
# Build the Windows binaries under Linux
set -eux -o pipefail

BIN_NAME=dcd

# Allow the script to be run from anywhere
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR

source setup-ldc-windows.sh

# Run LDC with cross-compilation
archiveName="$BIN_NAME-$VERSION-$OS-$ARCH_SUFFIX.zip"
echo "Building $archiveName"
mkdir -p bin
DC=ldmd2 make ldcclient ldcserver

cd bin
mv dcd-client dcd-client.exe
mv dcd-server dcd-server.exe
zip "$archiveName" "dcd-client.exe" "dcd-server.exe"
