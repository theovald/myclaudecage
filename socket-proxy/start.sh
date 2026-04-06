#!/usr/bin/env bash
#
# start.sh
# Finds the host macOS Podman socket, builds the proxy if needed, and starts it.
# It sets up variables that `claude-container.sh` uses to point DOCKER_HOST to
# the proxy's TCP port over host.containers.internal.
#

# Sets:     LISTEN_PORT, SOCKET_PROXY_PID, SOCKET_PROXY_OK, PODMAN_ENV
# Defines:  cleanup_proxy()

PROXY_DIR="$SCRIPT_DIR/socket-proxy"
PROXY_BIN="$PROXY_DIR/bin/socket-proxy"
LISTEN_PORT=$(( 23750 + (RANDOM % 1000) ))
SOCKET_PROXY_OK=false

# --- Find the host's container socket (Podman on macOS) ---
HOST_SOCK=""

# First try to ask podman directly
if command -v podman &>/dev/null; then
  HOST_SOCK=$(podman machine inspect 2>/dev/null | jq -r '.[0].ConnectionInfo.PodmanSocket.Path' 2>/dev/null || true)
fi

# Fallback paths
if [ -z "$HOST_SOCK" ] || [ "$HOST_SOCK" = "null" ] || [ ! -S "$HOST_SOCK" ]; then
  for sock in \
    "$HOME/.local/share/containers/podman/machine/podman.sock" \
    "$HOME/.local/share/containers/podman/machine/qemu/podman.sock" \
    "$HOME/.local/share/containers/podman/machine/podman-machine-default/podman.sock"; do
    if [ -S "$sock" ]; then
      HOST_SOCK="$sock"
      break
    fi
  done
fi

if [ -z "$HOST_SOCK" ] || [ ! -S "$HOST_SOCK" ]; then
  echo -e "${YELLOW}Warning: Podman socket not found. Container-in-container support disabled.${NC}" >&2
  return 0 2>/dev/null || true
fi

# --- Build the proxy binary ---
. "$PROXY_DIR/build.sh"

# --- Start the proxy ---
# Must bind to 0.0.0.0 — host.containers.internal inside the Podman VM resolves
# to the virtual network gateway, not the host loopback (127.0.0.1).
UPSTREAM_SOCKET="$HOST_SOCK" LISTEN_ADDR="0.0.0.0:$LISTEN_PORT" "$PROXY_BIN" &
SOCKET_PROXY_PID=$!
for i in $(seq 1 20); do
  if lsof -iTCP:$LISTEN_PORT -sTCP:LISTEN -P -n &>/dev/null; then
    break
  fi
  sleep 0.1
done

if ! lsof -iTCP:$LISTEN_PORT -sTCP:LISTEN -P -n &>/dev/null; then
  echo -e "${RED}Error: socket proxy failed to start${NC}" >&2
  kill "$SOCKET_PROXY_PID" 2>/dev/null
  return 0 2>/dev/null || true
fi

SOCKET_PROXY_OK=true
echo -e "${GREEN}Socket proxy active (PID $SOCKET_PROXY_PID on port $LISTEN_PORT)${NC}"

# --- Cleanup handler (caller should trap EXIT) ---
cleanup_proxy() {
  if [ -n "$SOCKET_PROXY_PID" ]; then
    kill "$SOCKET_PROXY_PID" 2>/dev/null
  fi
}

# --- Container-mode flags (used by claude-container.sh) ---
# We use TCP over host.containers.internal because macOS virtiofs does not
# support sharing Unix sockets with the Podman Linux VM.
PODMAN_ENV="-e DOCKER_HOST=tcp://host.containers.internal:$LISTEN_PORT
            -e TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=tcp://host.containers.internal:$LISTEN_PORT
            -e TESTCONTAINERS_RYUK_DISABLED=true
            -e TESTCONTAINERS_HOST_OVERRIDE=host.containers.internal"
