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

# --- Guard against mounting $HOME or its ancestors ---
abs_path() {
  if [ -d "$1" ]; then
    (cd "$1" 2>/dev/null && pwd -P)
  fi
}

PROJECT_FOLDER_ABS=$(abs_path "$PROJECT_FOLDER")
if [ -z "$PROJECT_FOLDER_ABS" ]; then
  echo -e "${RED}Error: project folder '$PROJECT_FOLDER' is not a directory${NC}" >&2
  exit 1
fi
HOME_ABS=$(abs_path "$HOME")

if [ "$PROJECT_FOLDER_ABS" = "$HOME_ABS" ] || [ "$PROJECT_FOLDER_ABS" = "/" ]; then
  echo -e "${RED}Error: refusing to mount '$PROJECT_FOLDER_ABS' as project folder${NC}" >&2
  echo -e "${YELLOW}Pass --folder=/path/to/project to specify a subdirectory.${NC}" >&2
  exit 1
fi

case "$HOME_ABS/" in
  "$PROJECT_FOLDER_ABS"/*)
    echo -e "${RED}Error: project folder '$PROJECT_FOLDER_ABS' contains \$HOME${NC}" >&2
    echo -e "${YELLOW}Pass --folder=/path/to/project to specify a subdirectory.${NC}" >&2
    exit 1
    ;;
esac

PROJECT_FOLDER="$PROJECT_FOLDER_ABS"
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

# --- Shared agents repository (sibling of project folder) ---
AGENTS_FOLDER_ABS=$(abs_path "$PROJECT_FOLDER/../agents")
AGENTS_MOUNT_ARG=""
if [ -z "$AGENTS_FOLDER_ABS" ]; then
  echo -e "${YELLOW}Warning: '../agents' not found next to project folder, skipping mount.${NC}" >&2
elif [ "$AGENTS_FOLDER_ABS" = "$HOME_ABS" ] || [ "$AGENTS_FOLDER_ABS" = "/" ]; then
  echo -e "${YELLOW}Warning: '../agents' resolves to '$AGENTS_FOLDER_ABS', skipping mount.${NC}" >&2
else
  AGENTS_MOUNT_ARG="-v $AGENTS_FOLDER_ABS:$CHOME/agents"
fi

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

# --- LLM proxy (optional) ---
# If ~/.claude-llmproxy.env exists, route Claude through an Anthropic-
# compatible proxy using a personal API key instead of the OAuth web
# login. Otherwise the container starts as before and Claude prompts
# for /login. The file is forwarded as-is via --env-file; expected
# variables are ANTHROPIC_BASE_URL, ANTHROPIC_API_KEY, ANTHROPIC_MODEL,
# and ANTHROPIC_SMALL_FAST_MODEL.
LLMPROXY_ENV_ARG=""
LLMPROXY_ENV_FILE="$HOME/.claude-llmproxy.env"
if [ -f "$LLMPROXY_ENV_FILE" ]; then
  LLMPROXY_ENV_ARG="--env-file $LLMPROXY_ENV_FILE"
  echo -e "${GREEN}Using LLM proxy (from $LLMPROXY_ENV_FILE)${NC}"
fi

GITCONFIG_MOUNT_ARG=""
if [ -f "$HOME/.gitconfig" ]; then
  GITCONFIG_MOUNT_ARG="-v $HOME/.gitconfig:$CHOME/.gitconfig.host:ro"
else
  echo -e "${YELLOW}Warning: '$HOME/.gitconfig' not found, skipping mount. Configure git user.name and user.email on the host to import them into the sandbox.${NC}" >&2
fi

podman run --rm -it \
  --name "$CONTAINER_NAME" \
  --hostname claude-sandbox \
  --userns=keep-id \
  --dns 1.1.1.1 --dns 8.8.8.8 \
  \
  -v "$PROJECT_FOLDER:$CHOME/$PROJECT_NAME" \
  $AGENTS_MOUNT_ARG \
  \
  -v "$HOME/.claude:$CHOME/.claude" \
  -v "$HOME/.claude.json:$CHOME/.claude.json" \
  -v "$HOME/.claude.json.backup:$CHOME/.claude.json.backup" \
  \
  -v "claude-uv-cache:$CHOME/.local/share/uv" \
  \
  $GITCONFIG_MOUNT_ARG \
  \
  $PORT_ARGS \
  \
  $GH_TOKEN_ARG \
  $LLMPROXY_ENV_ARG \
  $SHELL_MODE_ARG \
  $PODMAN_ENV \
  -e "COLORTERM=truecolor" \
  -e "NODE_OPTIONS=--dns-result-order=ipv4first" \
  -e "BUN_CONFIG_NO_CLEAR_TERMINAL=1" \
  \
  -w "$CHOME/$PROJECT_NAME" \
  "$IMAGE_NAME" "${CLAUDE_ARGS[@]}"
