#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Passed the sourced ROS_DISTRO into the Docker build as an explicit build argument.
# - Added image-name override for CI-candidate builds.
# - Aligned the default Docker SDK with the ros2cs .NET 10 test target.

set -euo pipefail

if [ -z "${ROS_DISTRO:-}" ]; then
    ROS_DISTRO=jazzy
    echo "ROS_DISTRO is not set; defaulting Docker build to '$ROS_DISTRO'." >&2
fi

IMAGE_NAME=${R2FU_DOCKER_IMAGE:-ros2-for-unity}
# .NET 10 matches the pinned ros2cs test target; override only after compatibility testing.
DOTNET_SDK_PACKAGE=${R2FU_DOTNET_SDK_PACKAGE:-dotnet-sdk-10.0}

export DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1}

docker build . \
    --build-arg ROS2_DISTRO="$ROS_DISTRO" \
    --build-arg DOTNET_SDK_PACKAGE="$DOTNET_SDK_PACKAGE" \
    --tag "$IMAGE_NAME"
