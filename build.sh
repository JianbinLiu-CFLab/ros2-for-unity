#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Added strict/fail-fast behavior for Linux builds.
# - Kept Ros2ForUnity asset deployment explicit after ros2cs build completion.

set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

display_usage() {
    echo "Usage: "
    echo ""
    echo "build.sh [--with-tests] [--standalone] [--clean-install]"
    echo ""
    echo "Options:"
    echo "--with-tests - build with tests"
    echo "--standalone - standalone version"
    echo "--clean-install - makes a clean installation, removes install directory before deploying"
}

if [ ! -d "$SCRIPTPATH/src/ros2cs" ]; then
    echo "Pull repositories with 'pull_repositories.sh' first."
    exit 1
fi

OPTIONS=()
STANDALONE=0
TESTS=0
CLEAN_INSTALL=0

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -t|--with-tests)
      OPTIONS+=("--with-tests")
      TESTS=1
      shift # past argument
      ;;
    -s|--standalone)
      if ! hash patchelf 2>/dev/null ; then
        echo "Patchelf missing. Standalone build requires patchelf. Install it via apt 'sudo apt install patchelf'."
        exit 1
      fi
      OPTIONS+=("--standalone")
      STANDALONE=1
      shift # past argument
      ;;
    -c|--clean-install)
      CLEAN_INSTALL=1
      shift # past argument
      ;;
    -h|--help)
      display_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      display_usage
      exit 1
      ;;
  esac
done

if [ "$CLEAN_INSTALL" == 1 ]; then
    echo "Cleaning install directory..."
    rm -rf "$SCRIPTPATH/install"
    mkdir -p "$SCRIPTPATH/install"
fi

if [ "$STANDALONE" == 1 ]; then
  python3 "$SCRIPTPATH/src/scripts/metadata_generator.py" --standalone
else
  python3 "$SCRIPTPATH/src/scripts/metadata_generator.py"
fi

# Delegate to ros2cs' own build entrypoint so R2FU does not duplicate colcon/toolchain policy.
if "$SCRIPTPATH/src/ros2cs/build.sh" "${OPTIONS[@]}"; then
    mkdir -p "$SCRIPTPATH/install/asset" && cp -R "$SCRIPTPATH/src/Ros2ForUnity" "$SCRIPTPATH/install/asset/"
    "$SCRIPTPATH/deploy_unity_plugins.sh" "$SCRIPTPATH/install/asset/Ros2ForUnity/Plugins/"
    for metadata_target in \
      "$SCRIPTPATH/install/asset/Ros2ForUnity/Plugins/Linux/x86_64/metadata_ros2cs.xml" \
      "$SCRIPTPATH/install/asset/Ros2ForUnity/Plugins/metadata_ros2cs.xml"; do
      cp "$SCRIPTPATH/src/Ros2ForUnity/metadata_ros2cs.xml" "$metadata_target"
    done
else
    echo "Ros2cs build failed!"
    exit 1
fi
