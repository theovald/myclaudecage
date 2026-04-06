#!/usr/bin/env bash
# test-vulns.sh — Regression tests for previously discovered vulnerabilities.
# Run from inside the sandbox container.
# Each test creates a container with a dangerous config and verifies it is blocked (HTTP 403).
# A VULNERABLE result means a regression — the proxy is no longer blocking the attack.
set -euo pipefail

CURL_SOCK=${DOCKER_HOST:-tcp://host.containers.internal:23750}
CURL_SOCK=${CURL_SOCK/tcp:/http:}
VULNS=0
MITIGATED=0
CLEANUP_IDS=()

get_sandbox_id() {
    curl -sf ${CURL_SOCK}/containers/json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Id'])"
}

create_container() {
    local json="$1"
    local name="${2:-}"
    local url="${CURL_SOCK}/containers/create"
    [ -n "$name" ] && url="${url}?name=${name}"
    curl -s "$url" \
        -d "$json" -H 'Content-Type: application/json'
}

get_http_code() {
    curl -s -o /dev/null -w "%{http_code}" "$@"
}

extract_id() {
    python3 -c "import sys,json; print(json.load(sys.stdin)['Id'][:12])"
}

cleanup() {
    echo ""
    echo "=== Cleaning up test containers ==="
    for cid in "${CLEANUP_IDS[@]}"; do
        curl -sf -X POST "${CURL_SOCK}/containers/$cid/stop?t=1" 2>/dev/null || true
        curl -sf -X DELETE "${CURL_SOCK}/containers/$cid" 2>/dev/null || true
    done
    echo "Done."
}
trap cleanup EXIT

SANDBOX_ID=$(get_sandbox_id)
SANDBOX_SHORT="${SANDBOX_ID:0:12}"
echo "Sandbox ID: $SANDBOX_SHORT"
echo ""

# -----------------------------------------------------------------------
# VULN 1: Relative path bind mount bypasses host-path filter
# -----------------------------------------------------------------------
echo "=== VULN 1: Relative path bind mount ==="
echo "Attack: Binds=[\"../../../etc:/mnt/host:ro\"] bypasses absolute-path check"

CODE=$(get_http_code "${CURL_SOCK}/containers/create?name=vuln1-relpath" \
    -d '{"Image":"ubuntu:25.10","Cmd":["sleep","30"],"HostConfig":{"Binds":["../../../etc:/mnt/host:ro"]}}' \
    -H 'Content-Type: application/json')

if [ "$CODE" = "201" ]; then
    echo "  VULNERABLE (HTTP $CODE - container created)"
    ((++VULNS))
    CID=$(curl -sf ${CURL_SOCK}/containers/vuln1-relpath/json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['Id'][:12])")
    CLEANUP_IDS+=("$CID")

    # Start and read host file
    curl -sf -X POST "${CURL_SOCK}/containers/$CID/start"
    sleep 1

    EXEC_RESP=$(curl -s "${CURL_SOCK}/containers/$CID/exec" \
        -d '{"Cmd":["cat","/mnt/host/hostname"],"AttachStdout":true,"AttachStderr":true}' \
        -H 'Content-Type: application/json')
    EXEC_ID=$(echo "$EXEC_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['Id'])")
    HOSTNAME=$(curl -s -X POST "${CURL_SOCK}/exec/$EXEC_ID/start" \
        -d '{"Detach":false}' -H 'Content-Type: application/json' --output - | tr -cd '[:print:]')
    echo "  Proof: host /etc/hostname = '$HOSTNAME'"
elif [ "$CODE" = "403" ]; then
    echo "  FIXED (HTTP $CODE - blocked)"
    ((++MITIGATED))
else
    echo "  ERROR (HTTP $CODE)"
fi

echo ""

# -----------------------------------------------------------------------
# VULN 2: PidMode=container:<SANDBOX> — share sandbox PID namespace
# -----------------------------------------------------------------------
echo "=== VULN 2: PidMode=container:SANDBOX ==="
echo "Attack: Share PID namespace with sandbox to see its processes and read /proc/*/environ"

CODE=$(get_http_code "${CURL_SOCK}/containers/create?name=vuln2-pidmode" \
    -d "{\"Image\":\"ubuntu:25.10\",\"Cmd\":[\"ps\",\"auxww\"],\"HostConfig\":{\"PidMode\":\"container:$SANDBOX_SHORT\"}}" \
    -H 'Content-Type: application/json')

if [ "$CODE" = "201" ]; then
    echo "  VULNERABLE (HTTP $CODE - container created)"
    ((++VULNS))
    CID=$(curl -sf ${CURL_SOCK}/containers/vuln2-pidmode/json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['Id'][:12])")
    CLEANUP_IDS+=("$CID")

    curl -sf -X POST "${CURL_SOCK}/containers/$CID/start"
    sleep 1

    echo "  Proof: processes visible from PID-shared container:"
    curl -s "${CURL_SOCK}/containers/$CID/logs?stdout=true" --output - \
        | tr -cd '[:print:]\n' | head -5 | sed 's/^/    /'
elif [ "$CODE" = "403" ]; then
    echo "  FIXED (HTTP $CODE - blocked)"
    ((++MITIGATED))
else
    echo "  ERROR (HTTP $CODE)"
fi

echo ""

# -----------------------------------------------------------------------
# VULN 3: UsernsMode=host — disable user namespace remapping
# -----------------------------------------------------------------------
echo "=== VULN 3: UsernsMode=host ==="
echo "Attack: Disable user namespace isolation so container UID 0 = host UID"

CODE=$(get_http_code "${CURL_SOCK}/containers/create?name=vuln3-userns" \
    -d '{"Image":"ubuntu:25.10","Cmd":["id"],"HostConfig":{"UsernsMode":"host"}}' \
    -H 'Content-Type: application/json')

if [ "$CODE" = "201" ]; then
    echo "  VULNERABLE (HTTP $CODE - container created)"
    ((++VULNS))
    CID=$(curl -sf ${CURL_SOCK}/containers/vuln3-userns/json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['Id'][:12])")
    CLEANUP_IDS+=("$CID")
elif [ "$CODE" = "403" ]; then
    echo "  FIXED (HTTP $CODE - blocked)"
    ((++MITIGATED))
else
    echo "  ERROR (HTTP $CODE)"
fi

echo ""

# -----------------------------------------------------------------------
# VULN 4: Sysctls — modify kernel parameters
# -----------------------------------------------------------------------
echo "=== VULN 4: Sysctls ==="
echo "Attack: Set kernel parameters like net.ipv4.ip_forward"

CODE=$(get_http_code "${CURL_SOCK}/containers/create?name=vuln4-sysctls" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"Sysctls":{"net.ipv4.ip_forward":"1"}}}' \
    -H 'Content-Type: application/json')

if [ "$CODE" = "201" ]; then
    echo "  VULNERABLE (HTTP $CODE - container created)"
    ((++VULNS))
    CID=$(curl -sf ${CURL_SOCK}/containers/vuln4-sysctls/json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['Id'][:12])")
    CLEANUP_IDS+=("$CID")
elif [ "$CODE" = "403" ]; then
    echo "  FIXED (HTTP $CODE - blocked)"
    ((++MITIGATED))
else
    echo "  ERROR (HTTP $CODE)"
fi

echo ""

# -----------------------------------------------------------------------
# VULN 5: Tmpfs over /proc — mask procfs protections
# -----------------------------------------------------------------------
echo "=== VULN 5: Tmpfs over /proc ==="
echo "Attack: Mount tmpfs over /proc with rw,exec to bypass procfs masking"

CODE=$(get_http_code "${CURL_SOCK}/containers/create?name=vuln5-tmpfs" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"Tmpfs":{"/proc":"rw,exec"}}}' \
    -H 'Content-Type: application/json')

if [ "$CODE" = "201" ]; then
    echo "  VULNERABLE (HTTP $CODE - container created)"
    ((++VULNS))
    CID=$(curl -sf ${CURL_SOCK}/containers/vuln5-tmpfs/json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['Id'][:12])")
    CLEANUP_IDS+=("$CID")
elif [ "$CODE" = "403" ]; then
    echo "  FIXED (HTTP $CODE - blocked)"
    ((++MITIGATED))
else
    echo "  ERROR (HTTP $CODE)"
fi

echo ""

# -----------------------------------------------------------------------
# VULN 6: NET_RAW capability in allowlist
# -----------------------------------------------------------------------
echo "=== VULN 6: NET_RAW capability ==="
echo "Attack: NET_RAW allows raw packet crafting and ARP spoofing"

CODE=$(get_http_code "${CURL_SOCK}/containers/create?name=vuln6-netraw" \
    -d '{"Image":"ubuntu:25.10","HostConfig":{"CapAdd":["NET_RAW"]}}' \
    -H 'Content-Type: application/json')

if [ "$CODE" = "201" ]; then
    echo "  VULNERABLE (HTTP $CODE - container created with NET_RAW)"
    ((++VULNS))
    CID=$(curl -sf ${CURL_SOCK}/containers/vuln6-netraw/json \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['Id'][:12])")
    CLEANUP_IDS+=("$CID")
elif [ "$CODE" = "403" ]; then
    echo "  FIXED (HTTP $CODE - blocked)"
    ((++MITIGATED))
else
    echo "  ERROR (HTTP $CODE)"
fi

echo ""
echo "==============================="
echo "Results: $VULNS vulnerable, $MITIGATED fixed"
[ "$VULNS" -eq 0 ] && echo "All vulnerabilities patched!" || echo "WARNING: $VULNS vulnerabilities remain!"
exit "$VULNS"
