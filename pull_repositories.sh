#!/bin/bash
set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

if [ -z "${ROS_DISTRO:-}" ]; then
    echo "Can't detect ROS2 version. Source your ROS 2 distro first. Humble and Jazzy are the maintained targets; Foxy/Galactic are historical."
    exit 1
fi

echo "========================================="
echo "* Pulling ros2cs repository:"
vcs import < "$SCRIPTPATH/ros2cs.repos"

echo ""
echo "========================================="
echo "Pulling custom repositories:"
vcs import < "$SCRIPTPATH/ros2_for_unity_custom_messages.repos"

echo ""
echo "========================================="
echo "Pulling ros2cs dependencies:"
cd "$SCRIPTPATH/src/ros2cs"
./get_repos.sh
cd - > /dev/null
