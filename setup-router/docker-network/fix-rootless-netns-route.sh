#!/bin/bash
set -euo pipefail

MAX_ATTEMPTS=60
RETRY_INTERVAL=20
NETNS_DIR="/run/user/$(id -u)/containers/networks/rootless-netns"
INTERNAL_NETWORKS_REGEX='^(internal-frontend|internal-backend|internal-p4)$'

has_rootless_default_route() {
    local netns_pid_file="$NETNS_DIR/rootless-netns-conn.pid"
    if [ -f "$netns_pid_file" ]; then
        local pid
        pid=$(cat "$netns_pid_file")
        if [ -d "/proc/$pid" ]; then
            grep -qP "^\S+\t00000000" /proc/$pid/net/route 2>/dev/null && return 0
        fi
    fi
    return 1
}

host_has_default_route() {
    ip -4 route show default 2>/dev/null | grep -q "via"
}

get_running_container_names() {
    podman ps --format '{{.Names}}' 2>/dev/null || true
}

get_service_unit_for_container() {
    local container="$1"
    podman inspect "$container" --format '{{index .Config.Labels "PODMAN_SYSTEMD_UNIT"}}' 2>/dev/null || true
}

get_network_mode_for_container() {
    local container="$1"
    podman inspect "$container" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null || true
}

get_network_names_for_container() {
    local container="$1"
    podman inspect "$container" --format '{{range $name, $_ := .NetworkSettings.Networks}}{{printf "%s\n" $name}}{{end}}' 2>/dev/null || true
}

container_has_default_route() {
    local container="$1"
    podman exec "$container" sh -lc "awk 'BEGIN{found=1} NR>1 && \$2 == \"00000000\" {found=0; exit} END{exit found}' /proc/net/route" >/dev/null 2>&1
}

collect_target_units() {
    local units_file="$1"
    : > "$units_file"

    while read -r container; do
        [ -z "$container" ] && continue

        local mode unit network_names matched_internal
        mode=$(get_network_mode_for_container "$container")
        unit=$(get_service_unit_for_container "$container")

        [ -z "$unit" ] && continue

        if [ "$mode" = "pasta" ]; then
            if ! container_has_default_route "$container"; then
                printf '%s\n' "$unit" >> "$units_file"
            fi
            continue
        fi

        if [ "$mode" != "bridge" ]; then
            continue
        fi

        matched_internal=0
        network_names=$(get_network_names_for_container "$container")
        while read -r network_name; do
            [ -z "$network_name" ] && continue
            if printf '%s\n' "$network_name" | grep -Eq "$INTERNAL_NETWORKS_REGEX"; then
                matched_internal=1
                break
            fi
        done <<EOF
$network_names
EOF

        if [ "$matched_internal" -eq 1 ] && ! has_rootless_default_route; then
            printf '%s\n' "$unit" >> "$units_file"
        fi
    done <<EOF
$(get_running_container_names)
EOF

    sort -u "$units_file" -o "$units_file"
}

restart_target_units() {
    local units_file="$1"
    local stopped=0

    if [ ! -s "$units_file" ]; then
        echo "No affected user units found"
        return 0
    fi

    echo "Stopping affected user units..."
    while read -r unit; do
        [ -z "$unit" ] && continue
        echo "  systemctl --user stop $unit"
        systemctl --user stop "$unit"
        stopped=1
    done < "$units_file"

    if [ "$stopped" -eq 1 ]; then
        sleep 2
    fi

    echo "Starting affected user units..."
    while read -r unit; do
        [ -z "$unit" ] && continue
        echo "  systemctl --user start $unit"
        systemctl --user start "$unit"
    done < "$units_file"
}

tmp_units=$(mktemp)
trap 'rm -f "$tmp_units"' EXIT

attempt=0
while [ $attempt -lt $MAX_ATTEMPTS ]; do
    if ! host_has_default_route; then
        echo "[attempt $((attempt+1))/$MAX_ATTEMPTS] Host has no default route yet, waiting..."
        sleep $RETRY_INTERVAL
        attempt=$((attempt+1))
        continue
    fi

    collect_target_units "$tmp_units"

    if [ ! -s "$tmp_units" ]; then
        if has_rootless_default_route; then
            echo "Default route already exists in rootless netns and no stale pasta units were found"
            exit 0
        fi

        echo "[attempt $((attempt+1))/$MAX_ATTEMPTS] Host default route found, but no affected running units were found"
        sleep $RETRY_INTERVAL
        attempt=$((attempt+1))
        continue
    fi

    echo "[attempt $((attempt+1))/$MAX_ATTEMPTS] Host default route found, restarting affected quadlet services..."

    echo "Affected units:"
    sed 's/^/  /' "$tmp_units"

    restart_target_units "$tmp_units"
    sleep 3

    if has_rootless_default_route; then
        echo "SUCCESS: Default route now present in rootless netns after service restart"
        exit 0
    fi

    echo "Route not yet applied after restart, retrying..."
    sleep $RETRY_INTERVAL
    attempt=$((attempt+1))
done

echo "FAILED: Could not fix rootless netns default route after $((MAX_ATTEMPTS * RETRY_INTERVAL)) seconds"
exit 1
