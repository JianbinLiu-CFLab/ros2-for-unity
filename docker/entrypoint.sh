#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Added R2FU_REPO and R2FU_REF overrides for fork-aware container builds.
# - Preserved the custom messages junction expected by the ros2cs workspace layout.

set -euo pipefail

source "/opt/ros/$ROS_DISTRO/setup.bash"

# These overrides let CI build a fork/ref without baking repository identity into the image.
R2FU_REPO=${R2FU_REPO:-https://github.com/JianbinLiu-CFLab/ros2-for-unity.git}
R2FU_REF=${R2FU_REF:-main}

echo "######################################################################"
echo ""
echo "Cloning '$R2FU_REF' from '$R2FU_REPO'"
echo ""
echo "######################################################################"
echo ""

git clone --branch "$R2FU_REF" "$R2FU_REPO" /workdir/.ros2-for-unity

shopt -s dotglob
mkdir -p /workdir/ros2-for-unity
mv /workdir/.ros2-for-unity/* /workdir/ros2-for-unity
cd /workdir/ros2-for-unity/ && ./pull_repositories.sh
mkdir -p "/home/$(whoami)"
git config --global --add safe.directory /workdir/ros2-for-unity
shopt -u dotglob

# Keep the historical ros2cs custom message path when the host mounted that directory.
if [ -d /workdir/custom_messages ]; then
  ln -sfn /workdir/custom_messages /workdir/ros2-for-unity/src/ros2cs/src/custom_messages
else
  echo "No /workdir/custom_messages mount found; skipping custom message symlink."
fi

echo ""
echo "######################################################################"
echo ""
echo "Welcome to 'ros2-for-unity' docker container. Your ROS2 distro is $ROS_DISTRO."
echo ""
echo "Type './build.sh' to build 'ros2-for-unity'. You will find installed libs on your host machine inside 'install' directory"
echo ""
echo "######################################################################"
echo ""

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec bash
