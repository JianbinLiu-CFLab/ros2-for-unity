#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Added fail-fast plugin deployment.
# - Made optional standalone-library copies non-fatal when the source directory is absent.
# - Added deployment timing and batched copy operations.

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
  echo "Ros2ForUnity plugin deployment timing summary:"
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

copy_find_batch() {
  local source_dir="$1"
  local destination_dir="$2"
  shift 2
  if [ ! -d "$source_dir" ]; then
    echo "Copy source directory does not exist: $source_dir" >&2
    return 1
  fi
  mkdir -p "$destination_dir"
  find "$source_dir" -maxdepth 1 "$@" -exec cp -L -t "$destination_dir" {} +
}

trap print_timing_summary EXIT

if [ $# -gt 0 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
  echo "Usage:"
  echo "deploy_unity_plugins.sh <PLUGINS_DIR>"
  echo ""
  echo "PLUGINS_DIR - Ros2ForUnity/Plugins folder."
  exit 0
fi

if [ $# -eq 0 ]; then
  echo "Usage:"
  echo "deploy_unity_plugins.sh <PLUGINS_DIR>"
  echo ""
  echo "PLUGINS_DIR - Ros2ForUnity/Plugins folder."
  exit 1
fi

pluginDir=$1

mkdir -p "${pluginDir}/Linux/x86_64/"
run_timed "managed DLL deploy" copy_find_batch "$SCRIPTPATH/install/lib/dotnet/" "${pluginDir}" -type f -not -name "*.pdb"
for required_managed in ros2cs_common.dll ros2cs_core.dll; do
  if [ ! -f "${pluginDir}/${required_managed}" ]; then
    echo "Required deployed managed file is missing: ${pluginDir}/${required_managed}" >&2
    exit 1
  fi
done
# Standalone/resource outputs are optional; non-standalone builds must still deploy the core plugins.
if [ -d "$SCRIPTPATH/install/standalone" ]; then
  run_timed "standalone native deploy" copy_find_batch "$SCRIPTPATH/install/standalone" "${pluginDir}/Linux/x86_64/" \( -type f -o -type l \)
fi
run_timed "native lib deploy" copy_find_batch "$SCRIPTPATH/install/lib/" "${pluginDir}/Linux/x86_64/" \( -type f -o -type l \) -not -name "*_python.so"
if [ -d "$SCRIPTPATH/install/resources" ]; then
  run_timed "resource native deploy" copy_find_batch "$SCRIPTPATH/install/resources" "${pluginDir}/Linux/x86_64/" \( -type f -o -type l \) -name "*.so"
fi

managed_count=$(find "${pluginDir}" -maxdepth 1 -type f | wc -l)
native_count=$(find "${pluginDir}/Linux/x86_64/" -maxdepth 1 -type f | wc -l)
echo "Deployment file counts: managed=${managed_count} native=${native_count}"
