#!/usr/bin/env bash
# Build the socket proxy binary using a Go container.
# Rebuilds only when main.go is newer than the binary.
#
# Requires: CONTAINER_CMD, SCRIPT_DIR
# Produces: socket-proxy/socket-proxy binary

PROXY_DIR="$SCRIPT_DIR/socket-proxy"
PROXY_BIN="$PROXY_DIR/socket-proxy"

if [ ! -x "$PROXY_BIN" ] || [ "$PROXY_BIN" -ot "$PROXY_DIR/main.go" ]; then
  echo -e "${GREEN}Building socket proxy...${NC}"
  $CONTAINER_CMD run --rm \
    -v "$PROXY_DIR:/src:Z" \
    -w /src \
    -e GOOS="$(uname -s | tr '[:upper:]' '[:lower:]')" \
    -e GOARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" \
    docker.io/library/golang:1.22 \
    go build -o socket-proxy .
fi
