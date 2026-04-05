#!/usr/bin/env bash
#
# open_url.sh
# Helper script to open URLs in the default browser. Useful when terminal
# line-wrapping breaks the claude.ai/oauth link into multiple lines, making
# it difficult to click directly.
#

# Strips whitespace from a URL and opens it in the default browser
url="$(echo "$*" | tr -d '[:space:]')"
echo "$url"
xdg-open "$url" 2>/dev/null || open "$url" 2>/dev/null
