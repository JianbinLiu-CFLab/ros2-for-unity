#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Added R2FU_REPO and R2FU_REF overrides for fork-aware container builds.
# - Preserved the custom messages junction expected by the ros2cs workspace layout.
# - Added explicit CI-candidate commands: r2fu-shell, r2fu-build, r2fu-smoke, and r2fu-ci.

set -euo pipefail

source "/opt/ros/$ROS_DISTRO/setup.bash"

# These overrides let CI build a fork/ref without baking repository identity into the image.
R2FU_REPO=${R2FU_REPO:-https://github.com/JianbinLiu-CFLab/ros2-for-unity.git}
R2FU_REF=${R2FU_REF:-main}
R2FU_WORKDIR=${R2FU_WORKDIR:-/workdir/ros2-for-unity}
R2FU_CLONE_TMP=${R2FU_CLONE_TMP:-/workdir/.ros2-for-unity}
R2FU_CUSTOM_MESSAGES_DIR=${R2FU_CUSTOM_MESSAGES_DIR:-/workdir/custom_messages}

if [ -z "${HOME:-}" ] || [ ! -w "${HOME:-/}" ]; then
  export HOME=/tmp/r2fu-home
fi
mkdir -p "$HOME"

prepare_workspace() {
  echo "######################################################################"
  echo ""
  echo "Preparing '$R2FU_REF' from '$R2FU_REPO'"
  echo ""
  echo "######################################################################"
  echo ""

  rm -rf "$R2FU_CLONE_TMP"
  if [[ "$R2FU_REF" =~ ^[0-9a-fA-F]{40}$ ]]; then
    git clone "$R2FU_REPO" "$R2FU_CLONE_TMP"
    cd "$R2FU_CLONE_TMP"
    git checkout "$R2FU_REF"
  else
    git clone --depth 1 --branch "$R2FU_REF" "$R2FU_REPO" "$R2FU_CLONE_TMP"
    cd "$R2FU_CLONE_TMP"
  fi

  mkdir -p "$R2FU_WORKDIR"
  find "$R2FU_WORKDIR" -mindepth 1 -maxdepth 1 ! -name install -exec rm -rf {} +

  shopt -s dotglob
  mv "$R2FU_CLONE_TMP"/* "$R2FU_WORKDIR"
  shopt -u dotglob
  rm -rf "$R2FU_CLONE_TMP"

  cd "$R2FU_WORKDIR"
  git config --global --add safe.directory "$R2FU_WORKDIR"

  ./pull_repositories.sh

  # Keep the historical ros2cs custom message path when the host mounted that directory.
  if [ -d "$R2FU_CUSTOM_MESSAGES_DIR" ]; then
    ln -sfn "$R2FU_CUSTOM_MESSAGES_DIR" "$R2FU_WORKDIR/src/ros2cs/src/custom_messages"
  else
    echo "No custom messages directory found at '$R2FU_CUSTOM_MESSAGES_DIR'; skipping custom message symlink."
  fi
}

r2fu_build() {
  prepare_workspace
  cd "$R2FU_WORKDIR"
  ./build.sh --standalone --with-tests "$@"
}

r2fu_test() {
  cd "$R2FU_WORKDIR/src/ros2cs"
  ./test.sh
}

r2fu_smoke() {
  /usr/local/bin/r2fu-ci-smoke "$R2FU_WORKDIR"
}

r2fu_shell() {
  prepare_workspace
  cd "$R2FU_WORKDIR"
  exec bash
}

case "${1:-}" in
  r2fu-shell)
    shift
    r2fu_shell "$@"
    ;;
  r2fu-build)
    shift
    r2fu_build "$@"
    exit 0
    ;;
  r2fu-smoke)
    shift
    r2fu_smoke "$@"
    exit 0
    ;;
  r2fu-ci)
    shift
    r2fu_build "$@"
    r2fu_test
    r2fu_smoke
    exit 0
    ;;
  r2fu-*)
    echo "Unknown R2FU container command: $1" >&2
    echo "Known commands: r2fu-shell, r2fu-build, r2fu-smoke, r2fu-ci" >&2
    exit 1
    ;;
esac

echo ""
echo "######################################################################"
echo ""
echo "Welcome to 'ros2-for-unity' docker container. Your ROS2 distro is $ROS_DISTRO."
echo ""
echo "CI commands:"
echo "  r2fu-shell"
echo "  r2fu-build [extra build.sh args]"
echo "  r2fu-smoke"
echo "  r2fu-ci [extra build.sh args]"
echo ""
echo "For an interactive prepared workspace, run: r2fu-shell"
echo ""
echo "######################################################################"
echo ""

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec bash
