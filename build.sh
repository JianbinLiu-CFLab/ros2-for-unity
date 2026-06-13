#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Added strict/fail-fast behavior for Linux builds.
# - Kept Ros2ForUnity asset deployment explicit after ros2cs build completion.
# - Added phase timing for R2FU wrapper build and deployment steps.

set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
TIMING_NAMES=()
TIMING_MS=()
TOTAL_START_NS=$(date +%s%N)

elapsed_ms() {
  local start_ns="$1"
  local end_ns
  end_ns=$(date +%s%N)
  echo $(((end_ns - start_ns) / 1000000))
}

record_timing() {
  TIMING_NAMES+=("$1")
  TIMING_MS+=("$2")
}

print_timing_summary() {
  local total_ms
  total_ms=$(elapsed_ms "$TOTAL_START_NS")
  echo ""
  echo "Ros2ForUnity build timing summary:"
  local i
  for ((i = 0; i < ${#TIMING_NAMES[@]}; i++)); do
    printf '  %-28s %8.3fs\n' "${TIMING_NAMES[$i]}" "$(awk "BEGIN { print ${TIMING_MS[$i]} / 1000 }")"
  done
  printf '  %-28s %8.3fs\n' "total" "$(awk "BEGIN { print $total_ms / 1000 }")"
}

run_timed() {
  local name="$1"
  shift
  local start_ns
  local status
  start_ns=$(date +%s%N)
  set +e
  "$@"
  status=$?
  set -e
  record_timing "$name" "$(elapsed_ms "$start_ns")"
  return "$status"
}

trap print_timing_summary EXIT

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
      if ! command -v patchelf >/dev/null 2>&1 ; then
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
    run_timed "clean install" bash -c 'echo "Cleaning install directory..." && rm -rf "$1" && mkdir -p "$1"' _ "$SCRIPTPATH/install"
fi

if [ "$STANDALONE" == 1 ]; then
  run_timed "metadata generation" python3 "$SCRIPTPATH/src/scripts/metadata_generator.py" --standalone
else
  run_timed "metadata generation" python3 "$SCRIPTPATH/src/scripts/metadata_generator.py"
fi

# Delegate to ros2cs' own build entrypoint so R2FU does not duplicate colcon/toolchain policy.
if run_timed "ros2cs build" "$SCRIPTPATH/src/ros2cs/build.sh" "${OPTIONS[@]}"; then
    if command -v rsync >/dev/null 2>&1; then
      run_timed "Unity asset staging" bash -c 'mkdir -p "$2" && rsync --archive --delete "$1/" "$2/"' _ "$SCRIPTPATH/src/Ros2ForUnity" "$SCRIPTPATH/install/asset/Ros2ForUnity"
    else
      run_timed "Unity asset staging" bash -c 'mkdir -p "$2" && rm -rf "$3" && cp -a "$1" "$2/"' _ "$SCRIPTPATH/src/Ros2ForUnity" "$SCRIPTPATH/install/asset" "$SCRIPTPATH/install/asset/Ros2ForUnity"
    fi
    run_timed "plugin deploy" "$SCRIPTPATH/deploy_unity_plugins.sh" "$SCRIPTPATH/install/asset/Ros2ForUnity/Plugins/" "$SCRIPTPATH/src/ros2cs/install"
    metadata_start_ns=$(date +%s%N)
    for metadata_target in \
      "$SCRIPTPATH/install/asset/Ros2ForUnity/Plugins/Linux/x86_64/metadata_ros2cs.xml" \
      "$SCRIPTPATH/install/asset/Ros2ForUnity/Plugins/metadata_ros2cs.xml"; do
      cp "$SCRIPTPATH/src/Ros2ForUnity/metadata_ros2cs.xml" "$metadata_target"
    done
    record_timing "metadata copy" "$(elapsed_ms "$metadata_start_ns")"
else
    echo "Ros2cs build failed!"
    exit 1
fi
