#!/usr/bin/env bash
# Strips whitespace from a URL and opens it in the default browser
url="$(echo "$*" | tr -d '[:space:]')"
echo "$url"
xdg-open "$url" 2>/dev/null || open "$url" 2>/dev/null
