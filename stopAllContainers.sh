#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
. "$SCRIPT_DIR/lib/os_type"
. "$SCRIPT_DIR/lib/colors"

. "$SCRIPT_DIR/lib/container_cmd"

x=$($CONTAINER_CMD ps -q)
if [ -n "$x" ]; then
  $CONTAINER_CMD stop $x
fi
x=$($CONTAINER_CMD ps --all -q)
if [ -n "$x" ]; then
  $CONTAINER_CMD rm -f $x
fi
