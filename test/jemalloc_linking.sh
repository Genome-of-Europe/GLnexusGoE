#!/bin/bash
# test that we can dynamically link jemalloc into glnexus_cli, and its
# built-in warning about whether jemalloc is present
set -e -o pipefail

echo "--- testing jemalloc warnings"

GLNEXUS_CLI="${1:-./glnexus_cli}"

LIBJEMALLOC_SO=""
for p in /usr/lib64/libjemalloc.so.2 /usr/lib64/libjemalloc.so /usr/local/lib/libjemalloc.so.2 /usr/lib/*-linux-gnu/libjemalloc.so.2 /usr/lib/*-linux-gnu/libjemalloc.so; do
    if [ -f "$p" ]; then
        LIBJEMALLOC_SO="$p"
        break
    fi
done
if [ -z "$LIBJEMALLOC_SO" ]; then
    LIBJEMALLOC_SO=$(ldconfig -p 2>/dev/null | grep -E "libjemalloc\.so(\.[0-9]+)? " | head -n1 | cut -f2 -d '>' | tr -d ' ')
fi
echo "path to libjemalloc.so: $LIBJEMALLOC_SO"
unset LD_PRELOAD

exit_code=0
MALLOC_CONF=bogus:true LD_PRELOAD=$LIBJEMALLOC_SO "$GLNEXUS_CLI" -h 2>&1 | grep 'Invalid conf pair' || exit_code=$?
if [ "$exit_code" -ne 0 ]; then
    echo "couldn't confirm jemalloc dynamic linking"
    exit 1
fi
"$GLNEXUS_CLI" -h 2>&1 | grep 'jemalloc absent' || exit_code=$?
if [ "$exit_code" -ne 0 ]; then
    echo "false-negative jemalloc warning"
    exit 1
fi
LD_PRELOAD=$LIBJEMALLOC_SO "$GLNEXUS_CLI" -h 2>&1 | grep 'jemalloc absent' || exit_code=$?
if [ "$exit_code" -eq 0 ]; then
    echo "false-positive jemalloc warning"
    exit 1
fi

echo "--- jemalloc warnings OK"
