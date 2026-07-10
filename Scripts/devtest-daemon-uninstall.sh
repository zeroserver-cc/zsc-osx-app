#!/bin/sh
# Tears down the throwaway devtest LaunchDaemon installed by
# devtest-daemon-install.sh. Safe to run even if it's already stopped/
# removed - each step tolerates "already gone."
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run this with sudo" >&2
    exit 1
fi

LABEL="cc.zeroserver.control-devtest"
PLIST_DEST="/Library/LaunchDaemons/${LABEL}.plist"

echo "==> Booting out ${LABEL} (if loaded)"
launchctl bootout "system/${LABEL}" 2>/dev/null || true

echo "==> Removing ${PLIST_DEST}"
rm -f "${PLIST_DEST}"

echo "Done. Verify with: launchctl print system/${LABEL} (should say \"Could not find service\")"
