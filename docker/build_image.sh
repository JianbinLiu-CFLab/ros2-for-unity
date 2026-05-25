#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Passed the sourced ROS_DISTRO into the Docker build as an explicit build argument.

set -euo pipefail

if [ -z "${ROS_DISTRO:-}" ]; then
    echo "Source your ros2 distro first."
    exit 1
fi

docker build . --build-arg ROS2_DISTRO="$ROS_DISTRO" --tag ros2-for-unity
