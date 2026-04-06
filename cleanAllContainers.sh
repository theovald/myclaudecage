#!/usr/bin/env bash
#
# cleanAllContainers.sh
# Drastic cleanup utility. Stops all containers and completely prunes the local
# Podman environment (containers, images, volumes, networks) to reclaim disk space.
#

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
. "$SCRIPT_DIR/lib/colors"

echo -e "${GREEN}Container usage before clean:${NC}"
podman system df
echo

"$SCRIPT_DIR/stopAllContainers.sh"

podman container prune -f
podman image prune -a -f
podman volume prune -f

podman network prune -f
podman system prune --volumes -af

echo
echo -e "${GREEN}Current container usage:${NC}"
podman system df
