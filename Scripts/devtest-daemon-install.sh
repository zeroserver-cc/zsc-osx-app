#!/bin/sh
# Installs the throwaway devtest LaunchDaemon (cc.zeroserver.control-devtest)
# used to manually verify AgentController's launchctl orchestration without
# needing the real zsc-agent installed. See Scripts/devtest-daemon.plist and
# the "Devtest daemon" section of CLAUDE.md.
#
# Run the app against it with:
#   ZSC_CONTROL_DEV_LABEL=cc.zeroserver.control-devtest swift run
#
# Needs sudo because LaunchDaemons live in /Library/LaunchDaemons and are
# bootstrapped into the system domain - exactly the same privilege
# requirement the real cc.zeroserver.agent has, which is the point.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run this with sudo (LaunchDaemons require root to install)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="cc.zeroserver.control-devtest"
PLIST_DEST="/Library/LaunchDaemons/${LABEL}.plist"

echo "==> Installing ${PLIST_DEST}"
cp "${SCRIPT_DIR}/devtest-daemon.plist" "${PLIST_DEST}"
chown root:wheel "${PLIST_DEST}"
chmod 644 "${PLIST_DEST}"

echo "==> Bootstrapping ${LABEL}"
launchctl bootstrap system "${PLIST_DEST}"

echo "==> Status:"
launchctl print "system/${LABEL}" | grep -E "state|pid" || true

echo ""
echo "Devtest daemon installed and running. Point the app at it with:"
echo "  ZSC_CONTROL_DEV_LABEL=${LABEL} swift run"
echo "When done, remove it with: sudo Scripts/devtest-daemon-uninstall.sh"
