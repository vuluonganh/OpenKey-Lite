#!/bin/sh
# Builds the engine tests and runs them.
#   Tests/run.sh           run hand-checked cases, then diff against golden.txt
#   Tests/run.sh --update  regenerate golden.txt from the current engine
set -e
cd "$(dirname "$0")"
ENGINE=../Sources/OpenKey/engine
BIN="${TMPDIR:-/tmp}/openkey_engine_test"

clang++ -std=c++17 -O1 -Wno-deprecated-declarations -I"$ENGINE" \
    "$ENGINE"/*.cpp engine_test.cpp -o "$BIN"

if [ "$1" = "--update" ]; then
    "$BIN" --golden > golden.txt
    echo "golden.txt updated ($(wc -l < golden.txt | tr -d ' ') lines)"
    exit 0
fi

"$BIN"
"$BIN" --golden > "$BIN.golden"
if diff -u golden.txt "$BIN.golden"; then
    echo "golden: no changes"
else
    echo "golden: output changed (see diff above)"
    exit 1
fi
