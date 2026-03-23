#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
. "$SCRIPT_DIR/lib/os_type"
. "$SCRIPT_DIR/lib/colors"

. "$SCRIPT_DIR/lib/container_cmd"

echo -e "${GREEN}Container usage before clean:${NC}"
$CONTAINER_CMD system df
echo

"$SCRIPT_DIR/stopAllContainers.sh"

$CONTAINER_CMD container prune -f
$CONTAINER_CMD image prune -a -f
if [ "$CONTAINER_CMD" = "docker" ]; then
  $CONTAINER_CMD volume prune -a -f
else
  $CONTAINER_CMD volume prune -f
fi

if [ "$CONTAINER_CMD" = "docker" ] && docker buildx version &>/dev/null; then
  docker buildx prune -f
fi

$CONTAINER_CMD network prune -f
$CONTAINER_CMD system prune --volumes -af

echo
echo -e "${GREEN}Current container usage:${NC}"
$CONTAINER_CMD system df
