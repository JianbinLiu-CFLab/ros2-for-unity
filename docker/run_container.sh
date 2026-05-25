#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Removed /etc/shadow mounting and kept only passwd/group read-only identity mappings.
# - Mounted install and custom_messages directories explicitly for local artifact builds.

set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

mkdir -p "$SCRIPTPATH/../install"
docker run \
--rm \
-it \
--name ros2-for-unity \
--user "$(id -u):$(id -g)" \
-v /etc/passwd:/etc/passwd:ro \
-v /etc/group:/etc/group:ro \
-v "$SCRIPTPATH/../install:/workdir/ros2-for-unity/install:rw" \
-v "$SCRIPTPATH/custom_messages:/workdir/custom_messages" \
ros2-for-unity \
bash
