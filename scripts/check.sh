#!/usr/bin/env bash
# Runs every check CI runs. Usage: bash scripts/check.sh [--quiet]
# --quiet: silent on success; on failure prints "check.sh: <step> failed" and the
# step's output to stderr. Exit 0 when all steps pass, 1 otherwise.
set -u
cd "$(dirname "$0")/.." || exit 1

quiet=0
[ "${1:-}" = "--quiet" ] && quiet=1

fail=0

step() {
    local name=$1
    shift
    if [ "$quiet" = 1 ]; then
        local out
        if ! out=$("$@" 2>&1); then
            { echo "check.sh: $name failed"; echo "$out"; } >&2
            fail=1
        fi
    else
        echo "== $name"
        "$@" || { echo "check.sh: $name failed" >&2; fail=1; }
    fi
}

parse() {
    local f
    for f in Core/*.lua Data/*.lua UI/*.lua; do
        luajit -bl "$f" > /dev/null || { echo "$f"; return 1; }
    done
}

step parse parse
step toc luajit tests/toc_check.lua
step unit luajit tests/run.lua
step smoke luajit tests/smoke.lua .

exit "$fail"
