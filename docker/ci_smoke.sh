#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Added a Docker CI-candidate smoke check for R2FU Linux artifact closure.

set -euo pipefail

workspace="${1:-${R2FU_WORKDIR:-/workdir/ros2-for-unity}}"
asset_dir="$workspace/install/asset/Ros2ForUnity"
plugin_dir="$asset_dir/Plugins"
native_dir="$plugin_dir/Linux/x86_64"

source "/opt/ros/$ROS_DISTRO/setup.bash"

require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "Required file missing: $path" >&2
    exit 1
  fi
}

require_glob() {
  local pattern="$1"
  shopt -s nullglob
  local matches=( $pattern )
  shopt -u nullglob
  if [ "${#matches[@]}" -eq 0 ]; then
    echo "Required file pattern missing: $pattern" >&2
    exit 1
  fi
  echo "${matches[0]}"
}

require_file "$plugin_dir/ros2cs_common.dll"
require_file "$plugin_dir/ros2cs_core.dll"

rcl_lib=$(require_glob "$native_dir/librcl.so*")
require_glob "$native_dir/librmw_implementation.so*" >/dev/null
require_glob "$native_dir/libyaml*.so*" >/dev/null

echo "Checking native dependency closure with ldd: $rcl_lib"
ldd "$rcl_lib" | tee /tmp/r2fu-ci-smoke-ldd.txt
if grep -q "not found" /tmp/r2fu-ci-smoke-ldd.txt; then
  echo "Native dependency closure has unresolved libraries." >&2
  exit 1
fi

echo "Checking ROS 2 CLI context availability."
timeout 30s ros2 topic list >/tmp/r2fu-ci-smoke-topic-list.txt

managed_count=$(find "$plugin_dir" -maxdepth 1 -type f | wc -l)
native_count=$(find "$native_dir" -maxdepth 1 -type f | wc -l)

echo "R2FU_DOCKER_CI_SMOKE_PASS managed=$managed_count native=$native_count rmw=${RMW_IMPLEMENTATION:-unset}"
