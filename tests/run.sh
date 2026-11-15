#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rtl8100-tests.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT

clang++ -std=gnu++98 -Wall -Wextra -Werror -g -O1 \
    -fsanitize=address,undefined \
    tests/logic_tests.cpp -o "$BUILD_DIR/logic_tests"
"$BUILD_DIR/logic_tests"

sh tests/source_invariants.sh
