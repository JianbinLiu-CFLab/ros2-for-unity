#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Removed /etc/shadow mounting and kept only passwd/group read-only identity mappings.
# - Mounted install and custom_messages directories explicitly for local artifact builds.
# - Added command passthrough and cache/output mount policy for CI-candidate runs.
# - Avoided forcing TTY allocation when running in non-interactive CI shells.

set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
IMAGE_NAME=${R2FU_DOCKER_IMAGE:-ros2-for-unity}
CONTAINER_NAME=${R2FU_DOCKER_CONTAINER_NAME:-ros2-for-unity}
R2FU_REPO=${R2FU_REPO:-https://github.com/JianbinLiu-CFLab/ros2-for-unity.git}
R2FU_REF=${R2FU_REF:-main}

mkdir -p "$SCRIPTPATH/../install"
mkdir -p "$SCRIPTPATH/cache"
mkdir -p "$SCRIPTPATH/custom_messages"

if [ "$#" -eq 0 ]; then
  set -- r2fu-shell
fi

DOCKER_TTY_ARGS=()
if [ -t 0 ] && [ "${R2FU_DOCKER_TTY:-auto}" != "false" ]; then
  DOCKER_TTY_ARGS=(-it)
fi

docker_args=(
  --rm
  "${DOCKER_TTY_ARGS[@]}"
  --name "$CONTAINER_NAME"
  --user "$(id -u):$(id -g)"
  -e "R2FU_REPO=$R2FU_REPO"
  -e "R2FU_REF=$R2FU_REF"
  -v /etc/passwd:/etc/passwd:ro
  -v /etc/group:/etc/group:ro
  -v "$SCRIPTPATH/../install:/workdir/ros2-for-unity/install:rw"
  -v "$SCRIPTPATH/custom_messages:/workdir/custom_messages"
  -v "$SCRIPTPATH/cache:/workdir/cache:rw"
)

docker run "${docker_args[@]}" "$IMAGE_NAME" "$@"
