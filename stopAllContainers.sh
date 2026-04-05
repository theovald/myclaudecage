#!/usr/bin/env bash
#
# stopAllContainers.sh
# Stops and removes all currently running Podman containers.
# Useful if the sandbox or proxy hangs.
#

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
. "$SCRIPT_DIR/lib/colors"

CONTAINER_CMD="podman"

x=$($CONTAINER_CMD ps -q)
if [ -n "$x" ]; then
  $CONTAINER_CMD stop $x
fi
x=$($CONTAINER_CMD ps --all -q)
if [ -n "$x" ]; then
  $CONTAINER_CMD rm -f $x
fi
