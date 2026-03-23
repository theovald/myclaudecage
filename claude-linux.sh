#!/usr/bin/env bash

# Script to start Claude in a safe environment
# Tested on 
#   * Ubuntu 25.10 

# Exploratory prompt to Claude:
# You're running in a bwrap sandbox. I'll be using this setup to develop Java backend and Javascript frontend.
# You should have access to editing my code, running tests and committing code to GitHub.
# Please verify that you have what you need.

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
. $SCRIPT_DIR/lib/os_type
. $SCRIPT_DIR/lib/colors

mkdir -p "$HOME/.claude"

FOR_CLAUDE="$HOME/4claude"
mkdir -p "$FOR_CLAUDE/usrlocal/lib"

[ ! -f "$FOR_CLAUDE/partial_passwd" ] && grep "$HOME" /etc/passwd > "$FOR_CLAUDE/partial_passwd"
[ ! -f $HOME/.claude.json ] && echo "{}" > $HOME/.claude.json
[ ! -f $HOME/.claude.json.backup ] && cp $HOME/.claude.json $HOME/.claude.json.backup

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

TOOLS="bash sh ls cp mv rm mkdir rmdir chmod touch cat echo grep xargs env 
git diff patch node curl wget tar gzip zip unzip ps kill 
uname dirname basename sed find sort head tail awk which
readlink tr wc cut jq gh whoami id mktemp file ssh"
BIN_TOOLS=""
for tool in $TOOLS; do
  target_path="/usr/bin/$tool"
  if [ -x "$target_path" ]; then
    BIN_TOOLS="$BIN_TOOLS --ro-bind $target_path $target_path"
  else
    echo "${YELLOW}Warning: '$tool' was not found in /usr/bin (skipping)${NC}" >&2
  fi
done


SOCKET_PROXY_OK=false
SOCKET_PROXY_PID=""
FILTERED_SOCK=""
if [ -z "$SETUP_PODMAN" ] && [ "$PODMAN_MODE" = "socket" ]; then
  if command -v podman &>/dev/null || command -v docker &>/dev/null; then
    . "$SCRIPT_DIR/lib/container_cmd"
    . "$SCRIPT_DIR/socket-proxy/start.sh"
  fi
  if ${SOCKET_PROXY_OK:-false}; then
    SETUP_PODMAN="--ro-bind /usr/bin/podman /usr/bin/podman \
                  --bind $FILTERED_SOCK $FILTERED_SOCK \
                  --ro-bind /usr/libexec/podman /usr/libexec/podman \
                  --ro-bind /usr/share/containers /usr/share/containers \
                  --bind $HOME/.local/share/containers $HOME/.local/share/containers \
                  --setenv DOCKER_HOST unix://$FILTERED_SOCK \
                  --setenv TESTCONTAINERS_RYUK_DISABLED true \
                  --setenv CONTAINER_HOST unix://$FILTERED_SOCK"
  fi
fi

if [ -z "$SETUP_JAVA" -a true ]; then
  SETUP_JAVA="--ro-bind $HOME/.sdkman $HOME/.sdkman \
              --bind $HOME/.m2 $HOME/.m2"
fi

if [ -z "$SETUP_JAVASCRIPT" -a true ]; then
  SYMLK_JAVASCRIPT=$(find /usr/bin -type l -printf "%p %l\n" | awk '$2 ~ /^\.\.\/share\/nodejs/ { sub(/^\.\.\/share\/nodejs/, "/usr/share/nodejs", $2); print "--symlink", $2, $1 }')
  SETUP_JAVASCRIPT="--ro-bind /usr/share/nodejs /usr/share/nodejs \
                    --ro-bind /usr/share/node_modules /usr/share/node_modules \
                    --ro-bind /usr/share/npm /usr/share/npm
                    --setenv NODE_EXTRA_CA_CERTS /etc/ssl/certs/ca-certificates.crt"
fi

# --- Check for SSH remotes ---

. "$SCRIPT_DIR/lib/detect_ssh_remotes.sh"
SETUP_SSH=""
if [ -n "$SSH_REPOS" ]; then
  echo -e "${YELLOW}Mounting ~/.ssh into sandbox.${NC}"
  [ ! -f "$HOME/.ssh/config" ] && touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
  SETUP_SSH="--ro-bind $HOME/.ssh/known_hosts $HOME/.ssh/known_hosts \
             --ro-bind $HOME/.ssh/config $HOME/.ssh/config \
             --setenv SSH_AUTH_SOCK $SSH_AUTH_SOCK \
             --bind $SSH_AUTH_SOCK $SSH_AUTH_SOCK"
fi

if [ -z "$SETUP_PYTHON" -a false ]; then
  SETUP_PYTHON="--ro-bind /usr/bin/python3 /usr/bin/python3"
fi

[ "$(type -t cleanup_proxy)" = "function" ] && trap cleanup_proxy EXIT

bwrap \
  --setenv HOME "$HOME" \
  --bind "$PROJECT_FOLDER" "$PROJECT_FOLDER" \
  \
  --ro-bind /usr/lib/x86_64-linux-gnu/ /usr/lib/x86_64-linux-gnu/ \
  --ro-bind /usr/lib/git-core/ /usr/lib/git-core/ \
  --ro-bind /usr/lib64 /usr/lib64 \
  --bind "$FOR_CLAUDE/usrlocal" /usr/local \
  --symlink /usr/bin /bin \
  --symlink /usr/lib /lib \
  --symlink /usr/lib64 /lib64 \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  \
  $BIN_TOOLS \
  \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --ro-bind /etc/ssl /etc/ssl \
  --ro-bind /etc/os-release /etc/os-release \
  --ro-bind "$FOR_CLAUDE/partial_passwd" /etc/passwd \
  --ro-bind /etc/ca-certificates /etc/ca-certificates \
  \
  --ro-bind "$HOME/.local/bin/claude" "$HOME/.local/bin/claude" \
  --ro-bind "$HOME/.local/share/claude" "$HOME/.local/share/claude" \
  --ro-bind "$HOME/.local/state/claude" "$HOME/.local/state/claude" \
  --bind "$HOME/.claude" "$HOME/.claude" \
  --bind "$HOME/.claude.json" "$HOME/.claude.json" \
  --bind "$HOME/.claude.json.backup" "$HOME/.claude.json.backup" \
  \
  $SETUP_SSH \
  \
  $SETUP_PYTHON \
  \
  $SETUP_JAVA \
  \
  \
  $SETUP_JAVASCRIPT \
  $SYMLK_JAVASCRIPT \
  \
  $SETUP_PODMAN \
  \
  --ro-bind "$HOME/.gitconfig" "$HOME/.gitconfig" \
  --setenv GH_TOKEN "$(gh auth token)" \
  --unshare-all \
  --share-net \
  --die-with-parent \
  -- claude "${CLAUDE_ARGS[@]}"
