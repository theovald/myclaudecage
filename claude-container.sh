#!/usr/bin/env bash

# Script to start Claude in a sandboxed Podman container
# Optimized for macOS, Python (uv), and JavaScript (Node.js)
#
# Usage:
#   ./claude-container.sh                     # build (if needed) and run
#   ./claude-container.sh --rebuild           # force rebuild the image
#   ./claude-container.sh --no-token          # run without GitHub token (push/PR outside sandbox)
#   ./claude-container.sh --shell             # start an empty bash shell instead of Claude
#   ./claude-container.sh --folder=/path      # mount an alternative working directory
#   ./claude-container.sh -p "prompt"         # pass arguments through to claude

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
. "$SCRIPT_DIR/lib/colors"

IMAGE_NAME="claude-sandbox"
CONTAINER_NAME="claude-sandbox-$$"
ENTRY_DIR="$SCRIPT_DIR/container"
USERNAME=$(whoami)

# Verify podman is installed
if ! command -v podman &>/dev/null; then
  echo -e "${RED}Error: podman not found. Please install it (e.g., brew install podman)${NC}" >&2
  exit 1
fi

# --- Parse script arguments ---

REBUILD=false
START_SHELL=false
GH_TOKEN_ENABLED=true
PROJECT_FOLDER="$PWD"
CLAUDE_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=true ;;
    --shell) START_SHELL=true ;;
    --no-token) GH_TOKEN_ENABLED=false ;;
    --folder=*) PROJECT_FOLDER="${arg#--folder=}" ;;
    *) CLAUDE_ARGS+=("$arg") ;;
  esac
done
PROJECT_NAME="${PROJECT_FOLDER##*/}"

# --- GitHub CLI authentication ---
if $GH_TOKEN_ENABLED; then
  if ! command -v gh &>/dev/null; then
    echo -e "${RED}Error: gh (GitHub CLI) not found. Install from https://cli.github.com${NC}" >&2
    exit 1
  fi
  gh auth token &>/dev/null || gh auth login
fi

# --- Build image if needed ---

if $REBUILD || ! podman image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo -e "${GREEN}Building Claude sandbox image...${NC}"
  podman build \
    --build-arg USERNAME="$USERNAME" \
    -t "$IMAGE_NAME" \
    -f "$SCRIPT_DIR/Containerfile.claude" \
    "$ENTRY_DIR"
fi

# --- Prerequisites ---

mkdir -p "$HOME/.claude" "$HOME/.local/share/uv"
[ ! -f "$HOME/.claude.json" ] && echo "{}" > "$HOME/.claude.json"
[ ! -f "$HOME/.claude.json.backup" ] && cp "$HOME/.claude.json" "$HOME/.claude.json.backup"

CHOME="/home/$USERNAME"

# --- Check available ports ---
CONTAINER_PORTS="3000 4200 5005 8000 8080"
PORT_ARGS=""
is_port_in_use() {
  if command -v ss &>/dev/null; then
    ss -tlnH "sport = :$1" 2>/dev/null | grep -q .
  else
    lsof -iTCP:"$1" -sTCP:LISTEN -P -n &>/dev/null
  fi
}
for port in $CONTAINER_PORTS; do
  if ! is_port_in_use "$port"; then
    PORT_ARGS="$PORT_ARGS -p $port:$port"
  else
    echo -e "${YELLOW}Warning: port $port is in use on the host, skipping mapping.${NC}"
  fi
done

# --- Container-in-container support ---
PODMAN_ENV=""

. "$SCRIPT_DIR/socket-proxy/start.sh"
if ! ${SOCKET_PROXY_OK:-false}; then
  echo -e "${RED}Error: socket proxy required but failed to start${NC}" >&2
  exit 1
fi
GH_TOKEN_FILE=""
cleanup() {
  cleanup_proxy
  [ -n "$GH_TOKEN_FILE" ] && rm -f "$GH_TOKEN_FILE"
}
trap cleanup EXIT

GH_TOKEN_ARG=""
if $GH_TOKEN_ENABLED; then
  GH_TOKEN_FILE=$(mktemp)
  printf 'GH_TOKEN=%s\n' "$(gh auth token)" > "$GH_TOKEN_FILE"
  GH_TOKEN_ARG="--env-file $GH_TOKEN_FILE"
fi

SHELL_MODE_ARG=""
if $START_SHELL; then
  SHELL_MODE_ARG="-e SHELL_MODE=1"
fi

podman run --rm -it \
  --name "$CONTAINER_NAME" \
  --hostname claude-sandbox \
  --userns=keep-id \
  --dns 1.1.1.1 --dns 8.8.8.8 \
  \
  -v "$PROJECT_FOLDER:$CHOME/$PROJECT_NAME" \
  \
  -v "$HOME/.claude:$CHOME/.claude" \
  -v "$HOME/.claude.json:$CHOME/.claude.json" \
  -v "$HOME/.claude.json.backup:$CHOME/.claude.json.backup" \
  \
  -v "claude-uv-cache:$CHOME/.local/share/uv" \
  \
  -v "$HOME/.gitconfig:$CHOME/.gitconfig.host:ro" \
  \
  $PORT_ARGS \
  \
  $GH_TOKEN_ARG \
  $SHELL_MODE_ARG \
  $PODMAN_ENV \
  -e "COLORTERM=truecolor" \
  -e "NODE_OPTIONS=--dns-result-order=ipv4first" \
  -e "BUN_CONFIG_NO_CLEAR_TERMINAL=1" \
  \
  -w "$CHOME/$PROJECT_NAME" \
  "$IMAGE_NAME" "${CLAUDE_ARGS[@]}"
