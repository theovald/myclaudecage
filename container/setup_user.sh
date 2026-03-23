#!/bin/bash
set -e

USERNAME=$1

if [ -z "${USERNAME}" ]; then
    echo "Usage: $0 <USERNAME>"
    exit 1
fi

# Remove any existing user with UID 1000 (e.g. Ubuntu's default 'ubuntu' user)
EXISTING_USER=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -n "${EXISTING_USER}" ] && [ "${EXISTING_USER}" != "${USERNAME}" ]; then
    userdel -r "${EXISTING_USER}" 2>/dev/null || true
fi

# Create user with default UID/GID (--userns=keep-id handles host mapping at runtime)
if ! id "${USERNAME}" &>/dev/null; then
    useradd --uid 1000 --shell /bin/bash --create-home ${USERNAME}
fi
