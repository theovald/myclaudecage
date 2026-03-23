#!/usr/bin/env bash
# test-blocked.sh — Verify that known attack vectors are blocked by the socket proxy.
# Run from inside the sandbox container. All tests should return HTTP 403.
set -euo pipefail

SOCK=/tmp/podman.sock
PASS=0
FAIL=0

get_sandbox_id() {
    curl -sf --unix-socket "$SOCK" http://localhost/containers/json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Id'])"
}

check_blocked() {
    local label="$1"
    shift
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$@")
    if [ "$http_code" = "403" ]; then
        echo "  PASS  $label (HTTP $http_code)"
        ((++PASS))
    else
        echo "  FAIL  $label (HTTP $http_code, expected 403)"
        ((++FAIL))
    fi
}

SANDBOX_ID=$(get_sandbox_id)
echo "Sandbox ID: ${SANDBOX_ID:0:12}"
echo ""
echo "=== Attacks that MUST be blocked (expect HTTP 403) ==="
echo ""

# --- Sandbox container operations ---

echo "-- Sandbox container operations --"

check_blocked "Archive READ on sandbox" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/$SANDBOX_ID/archive?path=/etc/hostname"

check_blocked "Archive WRITE on sandbox" \
    --unix-socket "$SOCK" -X PUT \
    "http://localhost/containers/$SANDBOX_ID/archive?path=/tmp" \
    -H 'Content-Type: application/x-tar' --data-binary @/dev/null

check_blocked "Stop sandbox" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/containers/$SANDBOX_ID/stop"

check_blocked "Kill sandbox" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/containers/$SANDBOX_ID/kill"

check_blocked "Restart sandbox" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/containers/$SANDBOX_ID/restart"

check_blocked "Pause sandbox" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/containers/$SANDBOX_ID/pause"

check_blocked "Unpause sandbox" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/containers/$SANDBOX_ID/unpause"

check_blocked "Delete sandbox" \
    --unix-socket "$SOCK" -X DELETE \
    "http://localhost/containers/$SANDBOX_ID"

check_blocked "Exec on sandbox" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/$SANDBOX_ID/exec" \
    -d '{"Cmd":["id"]}' -H 'Content-Type: application/json'

check_blocked "Logs on sandbox" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/$SANDBOX_ID/logs?stdout=true"

check_blocked "Attach to sandbox" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/containers/$SANDBOX_ID/attach"

check_blocked "Wait on sandbox" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/containers/$SANDBOX_ID/wait"

check_blocked "Rename sandbox" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/containers/$SANDBOX_ID/rename?name=pwned"

check_blocked "Start sandbox" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/containers/$SANDBOX_ID/start"

echo ""
echo "-- Blocked endpoints (allowlist) --"

check_blocked "Build endpoint" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/build"

check_blocked "Commit endpoint" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/commit"

check_blocked "Plugins endpoint" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/plugins"

check_blocked "Swarm endpoint" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/swarm/init"

check_blocked "Services endpoint" \
    --unix-socket "$SOCK" -X POST \
    "http://localhost/services/create"

check_blocked "Export sandbox filesystem" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/$SANDBOX_ID/export"

echo ""
echo "-- Dangerous container create options --"

check_blocked "Privileged mode" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"Privileged":true}}' \
    -H 'Content-Type: application/json'

check_blocked "Host PID namespace" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"PidMode":"host"}}' \
    -H 'Content-Type: application/json'

check_blocked "Host network namespace" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"NetworkMode":"host"}}' \
    -H 'Content-Type: application/json'

check_blocked "Host IPC namespace" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"IpcMode":"host"}}' \
    -H 'Content-Type: application/json'

check_blocked "Absolute host path bind mount" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"Binds":["/etc:/mnt/host:ro"]}}' \
    -H 'Content-Type: application/json'

check_blocked "Host bind via Mounts array" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"Mounts":[{"Type":"bind","Source":"/","Target":"/mnt","ReadOnly":true}]}}' \
    -H 'Content-Type: application/json'

check_blocked "SYS_PTRACE capability" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"CapAdd":["SYS_PTRACE"]}}' \
    -H 'Content-Type: application/json'

check_blocked "SYS_ADMIN capability" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"CapAdd":["SYS_ADMIN"]}}' \
    -H 'Content-Type: application/json'

check_blocked "ALL capabilities" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"CapAdd":["ALL"]}}' \
    -H 'Content-Type: application/json'

check_blocked "SecurityOpt seccomp=unconfined" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"SecurityOpt":["seccomp=unconfined"]}}' \
    -H 'Content-Type: application/json'

check_blocked "SecurityOpt apparmor=disabled" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"SecurityOpt":["apparmor=disabled"]}}' \
    -H 'Content-Type: application/json'

check_blocked "Device mappings" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"Devices":[{"PathOnHost":"/dev/null","PathInContainer":"/dev/null"}]}}' \
    -H 'Content-Type: application/json'

check_blocked "Host UTS namespace" \
    --unix-socket "$SOCK" \
    "http://localhost/containers/create" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"UTSMode":"host"}}' \
    -H 'Content-Type: application/json'

echo ""
echo "-- Dangerous network drivers --"

check_blocked "macvlan network" \
    --unix-socket "$SOCK" \
    "http://localhost/networks/create" \
    -d '{"Driver":"macvlan","Name":"evil"}' \
    -H 'Content-Type: application/json'

check_blocked "ipvlan network" \
    --unix-socket "$SOCK" \
    "http://localhost/networks/create" \
    -d '{"Driver":"ipvlan","Name":"evil"}' \
    -H 'Content-Type: application/json'

check_blocked "host network driver" \
    --unix-socket "$SOCK" \
    "http://localhost/networks/create" \
    -d '{"Driver":"host","Name":"evil"}' \
    -H 'Content-Type: application/json'

echo ""
echo "==============================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "All attacks blocked." || echo "WARNING: Some attacks were NOT blocked!"
exit "$FAIL"
