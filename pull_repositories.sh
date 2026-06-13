#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Updated supported ROS distribution messaging for Humble/Jazzy maintenance.
# - Made repository imports run from the repository root instead of the caller's current directory.

set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
custom_repos="$SCRIPTPATH/ros2_for_unity_custom_messages.repos"

if [ -z "${ROS_DISTRO:-}" ]; then
    echo "Can't detect ROS2 version. Source your ROS 2 distro first. Humble and Jazzy are the maintained targets; Foxy/Galactic are historical."
    exit 1
fi

echo "========================================="
echo "* Pulling ros2cs repository:"
# Anchor vcs imports at the repository root so callers can run this script from any CWD.
cd "$SCRIPTPATH"
vcs import --input "$SCRIPTPATH/ros2cs.repos"

echo ""
echo "========================================="
echo "Pulling custom repositories:"
if grep -qE '^[[:space:]]+type:' "$custom_repos"; then
    vcs import --input "$custom_repos"
else
    echo "No custom repositories defined; skipping vcs import."
fi

echo ""
echo "========================================="
echo "Pulling ros2cs dependencies:"
(cd "$SCRIPTPATH/src/ros2cs" && ./get_repos.sh)
