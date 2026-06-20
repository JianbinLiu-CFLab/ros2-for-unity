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
    printf '  %-28s %5d.%03ds\n' "${TIMING_NAMES[$i]}" "$((TIMING_MS[$i] / 1000))" "$((TIMING_MS[$i] % 1000))"
  done
  printf '  %-28s %5d.%03ds\n' "total" "$((total_ms / 1000))" "$((total_ms % 1000))"
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
    echo "build.sh [--with-tests] [--standalone] [--clean-install] [--strict-pin]"
    echo ""
    echo "Options:"
    echo "--with-tests - build with tests"
    echo "--standalone - standalone version"
    echo "--clean-install - removes R2FU install plus ros2cs build/install/log roots before deploying"
    echo "--strict-pin - fail when src/ros2cs does not match ros2cs.repos"
}

if [ ! -d "$SCRIPTPATH/src/ros2cs" ]; then
    echo "Pull repositories with 'pull_repositories.sh' first."
    exit 1
fi

safe_remove_dir() {
  local path="$1"
  local description="$2"
  local full_path

  if [ -z "$path" ]; then
    echo "Refusing to remove empty $description path." >&2
    return 1
  fi

  if ! full_path=$(python3 -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$path"); then
    echo "Could not resolve $description path: $path" >&2
    return 1
  fi
  if [ "$full_path" = "/" ]; then
    echo "Refusing to remove unsafe $description path: $full_path" >&2
    return 1
  fi

  if [ -e "$full_path" ]; then
    echo "Removing $description: $full_path"
    if ! rm -rf "$full_path"; then
      echo "Failed to remove $description: $full_path" >&2
      return 1
    fi
  fi
}

clean_install_roots() {
  safe_remove_dir "$SCRIPTPATH/install" "R2FU install directory" || return
  safe_remove_dir "$ROS2CS_BUILD_BASE" "ros2cs build base" || return
  safe_remove_dir "$ROS2CS_PATH/log" "ros2cs log base" || return
  safe_remove_dir "$ROS2CS_INSTALL_BASE" "ros2cs install base" || return
  mkdir -p "$SCRIPTPATH/install" || return
}

get_pinned_ros2cs_commit() {
  awk '
    /src\/ros2cs\// { in_ros2cs=1 }
    in_ros2cs && /^[[:space:]]+version:/ { print $2; exit }
  ' "$SCRIPTPATH/ros2cs.repos"
}

assert_ros2cs_pin() {
  local expected_commit="$1"
  local strict="$2"
  local actual_commit
  local message

  actual_commit=$(git -C "$ROS2CS_PATH" rev-parse HEAD 2>/dev/null || true)
  if [ -z "$actual_commit" ]; then
    message="Could not read src/ros2cs git HEAD; expected ros2cs.repos pin $expected_commit."
    if [ "$strict" = "1" ]; then
      echo "$message" >&2
      exit 1
    fi
    echo "WARNING: $message" >&2
    return
  fi

  if [ "$actual_commit" != "$expected_commit" ]; then
    message="src/ros2cs HEAD $actual_commit does not match ros2cs.repos pin $expected_commit."
    if [ "$strict" = "1" ]; then
      echo "$message" >&2
      exit 1
    fi
    echo "WARNING: $message" >&2
  fi
}

OPTIONS=()
STANDALONE=0
TESTS=0
CLEAN_INSTALL=0
STRICT_PIN=0

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
    --strict-pin)
      STRICT_PIN=1
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

if [ -z "${ROS_DISTRO:-}" ]; then
    echo "Can't detect ROS2 version. Source your ROS 2 distro first."
    exit 1
fi

ROS2CS_PATH=$(readlink -f "$SCRIPTPATH/src/ros2cs")
ROS2CS_BUILD_BASE="${R2FU_ROS2CS_BUILD_BASE:-$ROS2CS_PATH/build}"
ROS2CS_INSTALL_BASE="${R2FU_ROS2CS_INSTALL_BASE:-$ROS2CS_PATH/install}"
PINNED_ROS2CS_COMMIT=$(get_pinned_ros2cs_commit)
if [ -z "$PINNED_ROS2CS_COMMIT" ]; then
  echo "Could not find a pinned ros2cs commit in $SCRIPTPATH/ros2cs.repos" >&2
  exit 1
fi
assert_ros2cs_pin "$PINNED_ROS2CS_COMMIT" "$STRICT_PIN"

if [ "$CLEAN_INSTALL" == 1 ]; then
    run_timed "clean install" clean_install_roots
fi

if [ "$STANDALONE" == 1 ]; then
  run_timed "metadata generation" python3 "$SCRIPTPATH/src/scripts/metadata_generator.py" --standalone --ros2cs-path "$ROS2CS_PATH"
else
  run_timed "metadata generation" python3 "$SCRIPTPATH/src/scripts/metadata_generator.py" --ros2cs-path "$ROS2CS_PATH"
fi

# Delegate to ros2cs' own build entrypoint so R2FU does not duplicate colcon/toolchain policy.
ROS2CS_OPTIONS=("${OPTIONS[@]}" "--build-base" "$ROS2CS_BUILD_BASE" "--install-base" "$ROS2CS_INSTALL_BASE")
if run_timed "ros2cs build" "$ROS2CS_PATH/build.sh" "${ROS2CS_OPTIONS[@]}"; then
    if command -v rsync >/dev/null 2>&1; then
      run_timed "Unity asset staging" bash -c 'mkdir -p "$2" && rsync --archive --delete "$1/" "$2/"' _ "$SCRIPTPATH/src/Ros2ForUnity" "$SCRIPTPATH/install/asset/Ros2ForUnity"
    else
      run_timed "Unity asset staging" bash -c 'mkdir -p "$2" && rm -rf "$3" && cp -a "$1" "$2/"' _ "$SCRIPTPATH/src/Ros2ForUnity" "$SCRIPTPATH/install/asset" "$SCRIPTPATH/install/asset/Ros2ForUnity"
    fi
    run_timed "plugin deploy" "$SCRIPTPATH/deploy_unity_plugins.sh" "$SCRIPTPATH/install/asset/Ros2ForUnity/Plugins/" "$ROS2CS_INSTALL_BASE"
    metadata_start_ns=$(date +%s%N)
    if [ "$STANDALONE" == 1 ]; then
      python3 "$SCRIPTPATH/src/scripts/metadata_generator.py" --standalone --ros2cs-path "$ROS2CS_PATH" --plugins-dir "$SCRIPTPATH/install/asset/Ros2ForUnity/Plugins"
    else
      python3 "$SCRIPTPATH/src/scripts/metadata_generator.py" --ros2cs-path "$ROS2CS_PATH" --plugins-dir "$SCRIPTPATH/install/asset/Ros2ForUnity/Plugins"
    fi
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
