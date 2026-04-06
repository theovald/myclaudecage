#!/bin/bash
#
# entrypoint.sh
# Main container entrypoint. Configures the environment before handing over
# to Claude CLI, or drops into a bash shell when SHELL_MODE=1.
#

set -e

# Make uv available on PATH
export PATH="$HOME/.local/bin:${PATH}"

# Ensure installMethod is native
if [ -f "$HOME/.claude.json" ] && grep -q '"installMethod": "npm"' "$HOME/.claude.json"; then
  sed -i 's/"installMethod": "npm"/"installMethod": "native"/g' "$HOME/.claude.json"
fi

# Build git config from scratch — only inherit name/email from the host.
# Importing the full host gitconfig would bring in credential helpers,
# proxy settings, and hooks that should not run inside the container.
if [ -f "$HOME/.gitconfig.host" ]; then
  git_name=$(git config -f "$HOME/.gitconfig.host" user.name 2>/dev/null || true)
  git_email=$(git config -f "$HOME/.gitconfig.host" user.email 2>/dev/null || true)
  [ -n "$git_name" ]  && git config --global user.name  "$git_name"
  [ -n "$git_email" ] && git config --global user.email "$git_email"
fi

# Lock git to HTTPS only — block ssh://, git://, file://, ftp:// at protocol level.
git config --global protocol.allow never
git config --global protocol.https.allow always

# Rewrite SSH shorthand (git@github.com:) and legacy git:// to HTTPS.
git config --global url."https://github.com/".insteadOf "git@github.com:"
git config --global url."https://".insteadOf "git://"

# Use GitHub CLI as the HTTPS credential helper.
if [ -n "$GH_TOKEN" ] && command -v gh >/dev/null 2>&1; then
  gh auth setup-git 2>/dev/null || true
fi

if [ -n "$SHELL_MODE" ]; then
  echo "Interactive shell mode started."
  exec bash
else
  exec claude "$@"
fi
