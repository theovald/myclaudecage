#!/usr/bin/env bash

# Detect SSH remotes in a project folder.
#
# Scans .git/config files for git@ or ssh:// URLs, skipping
# target/ and node_modules/ directories.
#
# Requires: PROJECT_FOLDER to be set before sourcing.
# Sets:     SSH_REPOS (newline-separated list of matched config files,
#           empty if none found)
#
# Usage:    . ./lib/detect_ssh_remotes.sh

SSH_REPOS=$(find "$PROJECT_FOLDER" -maxdepth 3 \
  -type d \( -name target -o -name node_modules \) -prune -o \
  -name "config" -path "*/.git/config" \
  -exec grep -l "url = git@\|url = ssh://" {} \; 2>/dev/null)

if [ -n "$SSH_REPOS" ]; then
  echo -e "${YELLOW}Warning: SSH remotes detected in:${NC}"
  while IFS= read -r cfg; do
    echo -e "  ${YELLOW}${cfg%/.git/config}${NC}"
  done <<< "$SSH_REPOS"
fi
