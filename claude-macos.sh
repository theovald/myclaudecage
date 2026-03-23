#!/usr/bin/env bash

# Script to start Claude in a safe environment on macOS
# Uses sandbox-exec with a Seatbelt profile for filesystem isolation
#
# NOTE: sandbox-exec is deprecated by Apple but still functional on current
# macOS versions (tested through macOS 15 Sequoia). It provides file-system
# access control — not full container isolation like bwrap on Linux.
# For stronger isolation, consider running Claude inside a Docker container.
#
# Tested on
#   * (add your macOS version here)

# Exploratory prompt to Claude:
# You're running in a macOS sandbox. I'll be using this setup to develop Java backend and Javascript frontend.
# You should have access to editing my code, running tests and committing code to GitHub.
# Please verify that you have what you need.

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
. "$SCRIPT_DIR/lib/os_type"
. "$SCRIPT_DIR/lib/colors"

if ! $darwin; then
  echo "${RED}Error: This script is for macOS only. Use claude.sh for Linux.${NC}" >&2
  exit 1
fi

# Verify sandbox-exec is available
if ! command -v sandbox-exec >/dev/null 2>&1; then
  echo "${RED}Error: sandbox-exec not found. This tool ships with macOS.${NC}" >&2
  exit 1
fi

mkdir -p "$HOME/.claude"

[ ! -f "$HOME/.claude.json" ] && echo "{}" > "$HOME/.claude.json"
[ ! -f "$HOME/.claude.json.backup" ] && cp "$HOME/.claude.json" "$HOME/.claude.json.backup"

# --- Prerequisites ---

if ! command -v gh &>/dev/null; then
  echo -e "${RED}Error: gh (GitHub CLI) not found. Install from https://cli.github.com${NC}" >&2
  exit 1
fi
gh auth token &>/dev/null || gh auth login
gh auth setup-git

# --- Parse arguments ---

PROJECT_FOLDER="$PWD"
PODMAN_MODE="socket"
CLAUDE_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --folder) shift; PROJECT_FOLDER="$1" ;;
    --no-podman) PODMAN_MODE="none" ;;
    *) CLAUDE_ARGS+=("$1") ;;
  esac
  shift
done

# --- Check for SSH remotes ---

. "$SCRIPT_DIR/lib/detect_ssh_remotes.sh"

# --- Detect Homebrew prefix (Apple Silicon vs Intel) ---

if [ -d "/opt/homebrew" ]; then
  HOMEBREW_PREFIX="/opt/homebrew"
elif [ -d "/usr/local/Cellar" ]; then
  HOMEBREW_PREFIX="/usr/local"
else
  echo "${YELLOW}Warning: Homebrew not detected. Some tools may not be available.${NC}" >&2
  HOMEBREW_PREFIX=""
fi

# --- Find Claude binary ---

CLAUDE_BIN=$(command -v claude)
if [ -z "$CLAUDE_BIN" ]; then
  echo "${RED}Error: 'claude' not found in PATH${NC}" >&2
  exit 1
fi

# Resolve symlinks (macOS readlink doesn't support -f)
if command -v greadlink >/dev/null 2>&1; then
  CLAUDE_BIN_REAL=$(greadlink -f "$CLAUDE_BIN")
elif command -v realpath >/dev/null 2>&1; then
  CLAUDE_BIN_REAL=$(realpath "$CLAUDE_BIN")
else
  # Follow one level of symlink manually
  if [ -L "$CLAUDE_BIN" ]; then
    CLAUDE_BIN_REAL=$(readlink "$CLAUDE_BIN")
    # Handle relative symlinks
    case "$CLAUDE_BIN_REAL" in
      /*) ;;
      *)  CLAUDE_BIN_REAL="$(dirname "$CLAUDE_BIN")/$CLAUDE_BIN_REAL" ;;
    esac
  else
    CLAUDE_BIN_REAL="$CLAUDE_BIN"
  fi
fi
CLAUDE_DIR=$(dirname "$CLAUDE_BIN_REAL")

# --- Verify required tools ---

TOOLS="bash sh ls cp mv rm mkdir rmdir chmod touch cat echo grep xargs env
git diff patch node curl wget tar gzip zip unzip ps kill
uname dirname basename sed find sort head tail awk which
readlink tr wc cut jq gh whoami id mktemp file ssh"

for tool in $TOOLS; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "${YELLOW}Warning: '$tool' not found in PATH (skipping)${NC}" >&2
  fi
done

# --- Build sandbox profile rules for development tools ---

SANDBOX_RULES=""

# Java / SDKMAN (enabled by default, same as Linux variant)
if [ -z "$SETUP_JAVA" -a true ]; then
  if [ -d "$HOME/.sdkman" ]; then
    SANDBOX_RULES+="
;; --- Java / SDKMAN ---
(allow file-read* (subpath \"$HOME/.sdkman\"))"
  fi
  mkdir -p "$HOME/.m2"
  SANDBOX_RULES+="
(allow file-read* file-write* (subpath \"$HOME/.m2\"))"
fi

# JavaScript / Node.js (enabled by default)
if [ -z "$SETUP_JAVASCRIPT" -a true ]; then
  SANDBOX_RULES+="
;; --- Node.js / npm ---"
  [ -d "$HOME/.npm" ] && SANDBOX_RULES+="
(allow file-read* file-write* (subpath \"$HOME/.npm\"))"
  [ -d "$HOME/.nvm" ] && SANDBOX_RULES+="
(allow file-read* (subpath \"$HOME/.nvm\"))"
  [ -d "$HOME/node_modules" ] && SANDBOX_RULES+="
(allow file-read* file-write* (subpath \"$HOME/node_modules\"))"
fi

# Podman / Docker via socket proxy (enabled by default)
SOCKET_PROXY_OK=false
SOCKET_PROXY_PID=""
FILTERED_SOCK=""
if [ "$PODMAN_MODE" = "socket" ]; then
  if command -v podman &>/dev/null || command -v docker &>/dev/null; then
    . "$SCRIPT_DIR/lib/container_cmd"
    . "$SCRIPT_DIR/socket-proxy/start.sh"
  fi
fi

if ${SOCKET_PROXY_OK:-false}; then
  SANDBOX_RULES+="
;; --- Container runtime (via socket proxy) ---"
  # Filtered socket is in /tmp (already allowed by sandbox profile).
  # CLI tools still need access to config directories.
  [ -d "$HOME/.local/share/containers" ] && SANDBOX_RULES+="
(allow file-read* file-write* (subpath \"$HOME/.local/share/containers\"))"
  [ -d "$HOME/.docker" ] && SANDBOX_RULES+="
(allow file-read* (subpath \"$HOME/.docker\"))"
fi

# Python (disabled by default, same as Linux variant)
if [ -z "$SETUP_PYTHON" -a false ]; then
  PYTHON_BIN=$(command -v python3 2>/dev/null)
  [ -n "$PYTHON_BIN" ] && SANDBOX_RULES+="
;; --- Python ---
(allow file-read* (subpath \"$(dirname "$PYTHON_BIN")\"))"
fi

# --- Generate Seatbelt sandbox profile ---

: "${TMPDIR:=/tmp/}"
SANDBOX_PROFILE=$(mktemp "${TMPDIR}claude-sandbox-XXXXXX.sb")
trap 'rm -f "$SANDBOX_PROFILE"; [ "$(type -t cleanup_proxy)" = "function" ] && cleanup_proxy' EXIT

cat > "$SANDBOX_PROFILE" <<SBEOF
(version 1)
(deny default)

;; ============================================================
;; Process and system operations
;; ============================================================
(allow process-exec)
(allow process-fork)
(allow signal)
(allow process-info*)
(allow sysctl-read)
(allow mach*)
(allow ipc-posix*)
(allow file-ioctl)

;; ============================================================
;; Device access
;; ============================================================
(allow file-read* file-write* (subpath "/dev"))

;; ============================================================
;; System paths (read-only)
;; ============================================================
(allow file-read* (subpath "/usr/bin"))
(allow file-read* (subpath "/usr/lib"))
(allow file-read* (subpath "/usr/share"))
(allow file-read* (subpath "/bin"))
(allow file-read* (subpath "/sbin"))
(allow file-read* (subpath "/Library"))
(allow file-read* (subpath "/System"))
(allow file-read* (subpath "/private/var"))
(allow file-read* (subpath "/Applications/Xcode.app"))
(allow file-read* (subpath "/Library/Developer/CommandLineTools"))

;; ============================================================
;; Homebrew (read-only)
;; ============================================================
$([ -n "$HOMEBREW_PREFIX" ] && echo "(allow file-read* (subpath \"$HOMEBREW_PREFIX\"))")

;; ============================================================
;; System configuration (read-only)
;; ============================================================
(allow file-read* (subpath "/etc"))
(allow file-read* (subpath "/private/etc"))

;; ============================================================
;; Temp directories (read-write)
;; ============================================================
(allow file-read* file-write* (subpath "/tmp"))
(allow file-read* file-write* (subpath "/private/tmp"))
(allow file-read* file-write* (subpath "${TMPDIR}"))

;; ============================================================
;; Project directory (read-write)
;; ============================================================
(allow file-read* file-write* (subpath "$PROJECT_FOLDER"))

;; ============================================================
;; Claude configuration (read-write)
;; ============================================================
(allow file-read* file-write* (subpath "$HOME/.claude"))
(allow file-read* file-write* (literal "$HOME/.claude.json"))
(allow file-read* file-write* (literal "$HOME/.claude.json.backup"))

;; ============================================================
;; Claude installation (read-only)
;; ============================================================
(allow file-read* (subpath "$CLAUDE_DIR"))
$([ -d "$HOME/.local/share/claude" ] && echo "(allow file-read* (subpath \"$HOME/.local/share/claude\"))")
$([ -d "$HOME/.local/bin" ] && echo "(allow file-read* (subpath \"$HOME/.local/bin\"))")
$([ -d "$HOME/.local/state/claude" ] && echo "(allow file-read* (subpath \"$HOME/.local/state/claude\"))")
$([ -d "$HOME/Library/Application Support/Claude" ] && echo "(allow file-read* file-write* (subpath \"$HOME/Library/Application Support/Claude\"))")

;; ============================================================
;; Git configuration (read-only)
;; ============================================================
(allow file-read* (literal "$HOME/.gitconfig"))
$([ -d "$HOME/.config/git" ] && echo "(allow file-read* (subpath \"$HOME/.config/git\"))")

;; ============================================================
;; SSH (conditional — only when SSH remotes detected)
;; ============================================================
$([ -n "$SSH_REPOS" ] && echo "(allow file-read* (subpath \"$HOME/.ssh\"))")
$([ -n "$SSH_REPOS" ] && [ -n "$SSH_AUTH_SOCK" ] && echo "(allow file-read* file-write* (literal \"$SSH_AUTH_SOCK\"))")

;; ============================================================
;; Development tools
;; ============================================================
$SANDBOX_RULES

;; ============================================================
;; Network access
;; ============================================================
(allow network*)
SBEOF

# --- Environment variables ---

export GH_TOKEN="$(gh auth token)"
export NODE_EXTRA_CA_CERTS="/etc/ssl/cert.pem"

if ${SOCKET_PROXY_OK:-false}; then
  export DOCKER_HOST="unix://$FILTERED_SOCK"
  export CONTAINER_HOST="unix://$FILTERED_SOCK"
  export TESTCONTAINERS_RYUK_DISABLED=true
fi

exec sandbox-exec -f "$SANDBOX_PROFILE" "$CLAUDE_BIN" "${CLAUDE_ARGS[@]}"
