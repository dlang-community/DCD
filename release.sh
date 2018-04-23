#!/usr/bin/env bash
set -eux -o pipefail
VERSION=$(git describe --abbrev=0 --tags)
ARCH="${ARCH:-64}"
LDC_FLAGS=()
unameOut="$(uname -s)"
case "$unameOut" in
    Linux*) OS=linux; LDC_FLAGS=("-flto=full" "-linker=gold" "-static") ;;
    Darwin*) OS=osx; LDC_FLAGS+=("-L-macosx_version_min" "-L10.7" "-L-lcrt1.o"); ;;
    *) echo "Unknown OS: $unameOut"; exit 1
esac

case "$ARCH" in
    64) ARCH_SUFFIX="x86_64";;
    32) ARCH_SUFFIX="x86";;
    *) echo "Unknown ARCH: $ARCH"; exit 1
esac

archiveName="dcd-$VERSION-$OS-$ARCH_SUFFIX.tar.gz"

echo "Building $archiveName"
${MAKE:-make} ldcclient ldcserver LDC_FLAGS="${LDC_FLAGS[*]}"
tar cvfz "bin/$archiveName" -C bin dcd-server dcd-client
