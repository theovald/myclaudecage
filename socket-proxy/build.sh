#!/usr/bin/env bash
#
# build.sh
# Builds the Go-based socket proxy using a Podman golang container.
# This ensures users don't need Go installed on their macOS host.
#

# Build the socket proxy using a Go container
# Requires: SCRIPT_DIR

PROXY_DIR="$SCRIPT_DIR/socket-proxy"
PROXY_BIN="$PROXY_DIR/bin/socket-proxy"
GO_VERSION="1.26"

if [ ! -f "$PROXY_BIN" ] || [ "$PROXY_DIR/main.go" -nt "$PROXY_BIN" ]; then
  echo -e "${YELLOW}Building socket proxy...${NC}"
  mkdir -p "$PROXY_DIR/bin"
  podman run --rm \
    -v "$PROXY_DIR:/app" \
    -w /app \
    -e CGO_ENABLED=0 \
    -e GOOS=darwin \
    -e GOARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" \
    "golang:$GO_VERSION" go build -ldflags="-s -w" -o bin/socket-proxy main.go
fi
