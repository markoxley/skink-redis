#!/bin/bash
# test_live.sh — run the skink-redis live integration test against a
# real Redis server in a podman container.
#
#   ./test_live.sh            # start redis:7-alpine, run, tear down
#   SKINK_REDIS_DSN=... ./test_live.sh   # against an existing server
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${REDIS_IMAGE:-docker.io/library/redis:7-alpine}"
PORT="${REDIS_PORT:-16399}"
DSN="${SKINK_REDIS_DSN:-}"
CONTAINER=""

SKINK_HOME="${SKINK_HOME:-$HOME/.local/skink/std}"
SKINK_BIN="${SKINK:-$(command -v skink || echo "$HOME/.local/skink/bin/skink")}"

cleanup() {
    [ -n "$CONTAINER" ] && podman rm -f "$CONTAINER" >/dev/null 2>&1
    rm -f "$SCRIPT_DIR/.live_test_bin"
}
trap cleanup EXIT

if [ -z "$DSN" ]; then
    if ! command -v podman >/dev/null 2>&1; then
        echo "SKIP: podman not available and SKINK_REDIS_DSN unset"
        exit 0
    fi
    CONTAINER=$(podman run -d --rm -p "127.0.0.1:$PORT:6379" "$IMAGE")
    echo "started redis container $CONTAINER on :$PORT"
    # Wait for readiness.
    for i in $(seq 1 50); do
        if podman exec "$CONTAINER" redis-cli ping 2>/dev/null | grep -q PONG; then
            break
        fi
        sleep 0.2
    done
    DSN="redis://127.0.0.1:$PORT/0"
fi

SKINK_HOME="$SKINK_HOME" "$SKINK_BIN" -o "$SCRIPT_DIR/.live_test_bin" "$SCRIPT_DIR/live_test.skink" || exit 1
SKINK_REDIS_DSN="$DSN" "$SCRIPT_DIR/.live_test_bin"
