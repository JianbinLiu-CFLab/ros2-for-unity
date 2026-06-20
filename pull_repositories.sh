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
if ! vcs import --shallow --input "$SCRIPTPATH/ros2cs.repos"; then
    echo "vcs import ros2cs.repos failed." >&2
    exit 1
fi

echo ""
echo "========================================="
echo "Pulling custom repositories:"
if grep -qE '^[[:space:]]+type:' "$custom_repos"; then
    if ! vcs import --shallow --input "$custom_repos"; then
        echo "vcs import custom messages failed." >&2
        exit 1
    fi
else
    echo "No custom repositories defined; skipping vcs import."
fi

echo ""
echo "========================================="
echo "Pulling ros2cs dependencies:"
if ! (cd "$SCRIPTPATH/src/ros2cs" && ./get_repos.sh); then
    echo "ros2cs get_repos.sh failed." >&2
    exit 1
fi
