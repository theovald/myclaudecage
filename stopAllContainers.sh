#!/usr/bin/env bash
#
# stopAllContainers.sh
# Stops and removes all currently running Podman containers.
# Useful if the sandbox or proxy hangs.
#

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
. "$SCRIPT_DIR/lib/colors"

x=$(podman ps -q)
if [ -n "$x" ]; then
  podman stop $x
fi
x=$(podman ps --all -q)
if [ -n "$x" ]; then
  podman rm -f $x
fi
