#!/bin/bash

# $HOME/.config/containers/fix-rootless-netns-route.sh

# Fix rootless netns default route after reboot
# Problem: When using PPPoE (or other late-starting WAN connections),
# pasta starts before the default route exists, leaving the rootless netns
# without a default route. This causes aardvark-dns to fail forwarding
# external DNS queries.
# Solution: Reload podman networks which restarts the pasta connection
# with the now-available default route.

set -euo pipefail

MAX_ATTEMPTS=40
RETRY_INTERVAL=30
AARDVARK_PID_FILE="/run/user/$(id -u)/containers/networks/aardvark-dns/aardvark.pid"

attempt=0
while [ $attempt -lt $MAX_ATTEMPTS ]; do
    if [ ! -f "$AARDVARK_PID_FILE" ]; then
        echo "[attempt $((attempt+1))/$MAX_ATTEMPTS] aardvark-dns not running yet, waiting..."
        sleep $RETRY_INTERVAL
        attempt=$((attempt+1))
        continue
    fi

    AARDVARK_PID=$(cat "$AARDVARK_PID_FILE")
    if [ ! -d "/proc/$AARDVARK_PID" ]; then
        echo "[attempt $((attempt+1))/$MAX_ATTEMPTS] aardvark-dns process not found, waiting..."
        sleep $RETRY_INTERVAL
        attempt=$((attempt+1))
        continue
    fi

    if grep -qP "^\S+\t00000000" /proc/$AARDVARK_PID/net/route 2>/dev/null; then
        echo "Default route already exists in rootless netns"
        exit 0
    fi

    if ! ip -4 route show default 2>/dev/null | grep -q "via"; then
        echo "[attempt $((attempt+1))/$MAX_ATTEMPTS] Host has no default route yet, waiting..."
        sleep $RETRY_INTERVAL
        attempt=$((attempt+1))
        continue
    fi

    echo "[attempt $((attempt+1))/$MAX_ATTEMPTS] Host default route found, reloading podman networks..."
    podman network reload --all 2>&1 || {
        echo "podman network reload failed, retrying..."
        sleep $RETRY_INTERVAL
        attempt=$((attempt+1))
        continue
    }

    sleep 1

    AARDVARK_PID=$(cat "$AARDVARK_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$AARDVARK_PID" ] && [ -d "/proc/$AARDVARK_PID" ] && \
       grep -qP "^\S+\t00000000" /proc/$AARDVARK_PID/net/route 2>/dev/null; then
        echo "SUCCESS: Default route now present in rootless netns"
        exit 0
    fi

    echo "Route not yet applied, retrying..."
    sleep $RETRY_INTERVAL
    attempt=$((attempt+1))
done

echo "FAILED: Could not fix rootless netns default route after $((MAX_ATTEMPTS * RETRY_INTERVAL)) seconds"
exit 1