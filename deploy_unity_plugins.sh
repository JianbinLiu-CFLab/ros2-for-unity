#!/bin/bash
# Copyright (c) 2026 Jianbin Liu.
#
# Purpose:
# - Added fail-fast plugin deployment.
# - Made optional standalone-library copies non-fatal when the source directory is absent.
# - Added deployment timing and batched copy operations.

set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
TIMING_NAMES=()
TIMING_MS=()
now_ns() {
  # Bash 5+ exposes EPOCHREALTIME without spawning date; older shells use date as a fallback.
  if [ -n "${EPOCHREALTIME:-}" ]; then
    local realtime="$EPOCHREALTIME"
    local seconds="${realtime%%[.,]*}"
    local micros="${realtime#*[.,]}"
    printf '%s%06d000\n' "$seconds" "$((10#$micros))"
  else
    date +%s%N
  fi
}

TOTAL_START_NS=$(now_ns)

elapsed_ms() {
  local start_ns="$1"
  local end_ns
  end_ns=$(now_ns)
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
    printf '  %-28s %5d.%03ds\n' "${TIMING_NAMES[$i]}" "$((TIMING_MS[$i] / 1000))" "$((TIMING_MS[$i] % 1000))"
  done
  printf '  %-28s %5d.%03ds\n' "total" "$((total_ms / 1000))" "$((total_ms % 1000))"
}

run_timed() {
  local name="$1"
  shift
  local start_ns
  local status
  start_ns=$(now_ns)
  # Temporarily relax errexit so timing is recorded before the original status is returned.
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
  local source_root
  shift 2
  if [ ! -d "$source_dir" ]; then
    echo "Copy source directory does not exist: $source_dir" >&2
    return 1
  fi
  mkdir -p "$destination_dir"
  source_root="${source_dir%/}"
  if command -v rsync > /dev/null 2>&1; then
    local files=()
    local file
    while IFS= read -r -d '' file; do
      files+=("${file#"$source_root"/}")
    done < <(find "$source_root" -maxdepth 1 "$@" -printf '%p\0')
    if [ ${#files[@]} -eq 0 ]; then
      return 0
    fi
    printf '%s\0' "${files[@]}" | rsync -a --checksum --copy-links --from0 --files-from=- "$source_root/" "$destination_dir/"
    return
  fi
  find "$source_dir" -maxdepth 1 "$@" -exec cp -L -t "$destination_dir" {} +
}

remove_deployed_plugin_outputs() {
  # Remove both the current native output and the legacy nested StreamingAssets layout from older builds.
  rm -rf "$nativePluginDir" "$streamingAssetsShareDestination" "$legacyNestedStreamingAssets" || return
  find "$pluginDir" -maxdepth 1 -type f \( -name "*.dll" -o -name "metadata_ros2cs.xml" \) -delete || return
}

copy_file_preserving_relative_path() {
  # Copy selected ament-index files while preserving their resource_index-relative names.
  local source_root="$1"
  local destination_root="$2"
  local relative_path="$3"
  local source_file="$source_root/$relative_path"
  local destination_file="$destination_root/$relative_path"

  if [ ! -f "$source_file" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$destination_file")" || return
  cp -f "$source_file" "$destination_file"
}

copy_ros_runtime_share_closure() {
  local source_share="$1"
  local destination_share="$2"
  # These package entries cover RMW selection, typesupport lookup, and dynamic type backend discovery.
  local runtime_packages=(
    ament_index_cpp
    fastcdr
    fastdds
    fastrtps_cmake_module
    foonathan_memory_vendor
    rcpputils
    rcutils
    rmw
    rmw_dds_common
    rmw_fastrtps_cpp
    rmw_fastrtps_shared_cpp
    rmw_implementation
    rmw_implementation_cmake
    rmw_security_common
    rosidl_buffer_backend
    rosidl_dynamic_typesupport
    rosidl_dynamic_typesupport_fastrtps
    rosidl_runtime_c
    rosidl_runtime_cpp
    rosidl_typesupport_c
    rosidl_typesupport_cpp
    rosidl_typesupport_fastrtps_c
    rosidl_typesupport_fastrtps_cpp
    rosidl_typesupport_introspection_c
    rosidl_typesupport_introspection_cpp
  )
  # Resource indexes are copied package-by-package to avoid pulling large unrelated share directories.
  local resource_indexes=(
    packages
    package_run_dependencies
    parent_prefix_path
    rmw_output_patterns
    rmw_output_prefixes
    rmw_typesupport
    rmw_typesupport_c
    rmw_typesupport_cpp
    rosidl_typesupport_c
    rosidl_typesupport_cpp
  )
  local package_name
  local resource_index

  for package_name in "${runtime_packages[@]}"; do
    for resource_index in "${resource_indexes[@]}"; do
      copy_file_preserving_relative_path \
        "$source_share" \
        "$destination_share" \
        "ament_index/resource_index/$resource_index/$package_name" || return
    done
  done
}

deploy_ros_runtime_share_closure() {
  local source_share="$1"
  copy_ros_runtime_share_closure "$source_share" "${nativePluginDir}/share" &&
    copy_ros_runtime_share_closure "$source_share" "$streamingAssetsShareDestination"
}

emit_ros_root_candidates() {
  if [ -n "${ROS2_ROOT:-}" ]; then
    printf '%s\n' "$ROS2_ROOT"
  fi

  if [ -n "${LD_LIBRARY_PATH:-}" ]; then
    local old_ifs="$IFS"
    local lib_dir
    IFS=:
    for lib_dir in $LD_LIBRARY_PATH; do
      IFS="$old_ifs"
      if [ -n "$lib_dir" ] && [ "$(basename "$lib_dir")" = "lib" ]; then
        dirname "$lib_dir"
      fi
      IFS=:
    done
    IFS="$old_ifs"
  fi

  if [ -n "${ROS_DISTRO:-}" ] && [ -d "/opt/ros/$ROS_DISTRO" ]; then
    printf '%s\n' "/opt/ros/$ROS_DISTRO"
  fi
}

emit_ros_library_search_dirs() {
  local root
  while IFS= read -r root; do
    if [ -n "$root" ]; then
      printf '%s\n' "$root/lib"
    fi
  done < <(emit_ros_root_candidates)

  if [ -n "${LD_LIBRARY_PATH:-}" ]; then
    local old_ifs="$IFS"
    local lib_dir
    IFS=:
    for lib_dir in $LD_LIBRARY_PATH; do
      IFS="$old_ifs"
      if [ -n "$lib_dir" ]; then
        printf '%s\n' "$lib_dir"
      fi
      IFS=:
    done
    IFS="$old_ifs"
  fi
}

find_ros_runtime_files() {
  local pattern="$1"
  local search_dir
  while IFS= read -r search_dir; do
    if [ -d "$search_dir" ]; then
      compgen -G "$search_dir/$pattern" || true
    fi
  done < <(emit_ros_library_search_dirs | sort -u)
}

copy_ros_root_runtime_libs() {
  # These libraries are resolved from the active ROS root/LD_LIBRARY_PATH, not from the ros2cs install prefix.
  local patterns=(
    "libclass_loader.so*"
    "libfastdds.so*"
    "libfastrtps.so*"
    "librcl_logging_implementation.so*"
    "librcl_logging_spdlog.so*"
    "librcl_logging_noop.so*"
    "librosidl_buffer_backend_registry.so*"
  )
  local pattern
  local files
  local file
  local search_dirs
  search_dirs=$(emit_ros_library_search_dirs | sort -u | paste -sd ';' -)

  for pattern in "${patterns[@]}"; do
    files=$(find_ros_runtime_files "$pattern" | sort -u)
    if [ -z "$files" ]; then
      echo "WARNING: Could not find required ROS2 runtime library pattern '$pattern'. Searched: $search_dirs" >&2
      continue
    fi
    while IFS= read -r file; do
      cp -Lf "$file" "$nativePluginDir/" || return
    done <<< "$files"
  done
}

copy_ldconfig_runtime_libs() {
  # Some ROS Linux packages depend on distribution-provided shared libraries that
  # are outside the ROS prefix. Copy only the known runtime names needed by the
  # standalone plugin closure.
  if ! command -v ldconfig > /dev/null 2>&1; then
    echo "WARNING: ldconfig is unavailable; skipping system runtime library copy." >&2
    return 0
  fi

  local sonames=(
    "libyaml-cpp.so"
    "libyaml-cpp.so.0.8"
    "libyaml-0.so.2"
  )
  local soname
  local file

  for soname in "${sonames[@]}"; do
    file=$(ldconfig -p 2>/dev/null | awk -v name="$soname" '$1 == name { print $NF; exit }')
    if [ -z "$file" ]; then
      continue
    fi
    cp -Lf "$file" "$nativePluginDir/" || return
  done
}

copy_metadata_file() {
  local destination="$1"
  local metadata_source="$SCRIPTPATH/src/Ros2ForUnity/metadata_ros2cs.xml"

  if [ ! -f "$metadata_source" ]; then
    echo "metadata_ros2cs.xml source file is missing: $metadata_source" >&2
    return 1
  fi

  mkdir -p "$destination" || return
  cp -f "$metadata_source" "$destination/" || return
  if [ ! -f "$destination/metadata_ros2cs.xml" ]; then
    echo "Required deployed ros2cs metadata is missing: $destination/metadata_ros2cs.xml" >&2
    return 1
  fi
}

deploy_metadata_files() {
  # Keep metadata next to platform native libraries and at Plugins root for platform-agnostic readers.
  copy_metadata_file "$pluginDir" &&
    copy_metadata_file "$nativePluginDir"
}

# Always print timing, including failing deployments, so long-running phases are visible in CI logs.
trap print_timing_summary EXIT

if [ $# -gt 0 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
  echo "Usage:"
  echo "deploy_unity_plugins.sh <PLUGINS_DIR> [INSTALL_ROOT]"
  echo ""
  echo "PLUGINS_DIR - Ros2ForUnity/Plugins folder."
  echo "INSTALL_ROOT - ros2cs install root, default = '<script dir>/install'."
  exit 0
fi

if [ $# -eq 0 ]; then
  echo "Usage:"
  echo "deploy_unity_plugins.sh <PLUGINS_DIR> [INSTALL_ROOT]"
  echo ""
  echo "PLUGINS_DIR - Ros2ForUnity/Plugins folder."
  echo "INSTALL_ROOT - ros2cs install root, default = '<script dir>/install'."
  exit 1
fi

pluginDir=${1%/}
installRoot=${2:-"$SCRIPTPATH/install"}
nativePluginDir="${pluginDir}/Linux/x86_64"
assetRoot=$(dirname "$pluginDir")
assetInstallRoot=$(dirname "$assetRoot")
legacyNestedStreamingAssets="${assetRoot}/StreamingAssets"
streamingAssetsShareDestination="${assetInstallRoot}/StreamingAssets/Ros2ForUnity/share"

if [ ! -d "$pluginDir" ]; then
  echo "Plugins directory: '$pluginDir' doesn't exist. Please create it first manually." >&2
  exit 1
fi

require_file_glob() {
  local description="$1"
  local pattern="$2"
  if ! compgen -G "$pattern" > /dev/null; then
    echo "Required deployed ${description} is missing: expected ${pattern}" >&2
    exit 1
  fi
}

require_any_file_glob() {
  local description="$1"
  shift
  local pattern
  for pattern in "$@"; do
    if compgen -G "$pattern" > /dev/null; then
      return 0
    fi
  done
  echo "Required deployed ${description} is missing: expected one of: $*" >&2
  exit 1
}

run_timed "stale plugin cleanup" remove_deployed_plugin_outputs
mkdir -p "${nativePluginDir}/"
run_timed "managed DLL deploy" copy_find_batch "$installRoot/lib/dotnet/" "${pluginDir}" -type f -not -name "*.pdb"
for required_managed in ros2cs_common.dll ros2cs_core.dll; do
  if [ ! -f "${pluginDir}/${required_managed}" ]; then
    echo "Required deployed managed file is missing: ${pluginDir}/${required_managed}" >&2
    exit 1
  fi
done
# Standalone/resource outputs are optional; non-standalone builds must still deploy the core plugins.
if [ -d "$installRoot/standalone" ]; then
  run_timed "standalone native deploy" copy_find_batch "$installRoot/standalone" "${nativePluginDir}/" \( -type f -o -type l \)
fi
run_timed "native lib deploy" copy_find_batch "$installRoot/lib/" "${nativePluginDir}/" \( -type f -o -type l \) -not -name "*_python.so"
if [ -d "$installRoot/resources" ]; then
  run_timed "resource native deploy" copy_find_batch "$installRoot/resources" "${nativePluginDir}/" \( -type f -o -type l \) -name "*.so"
fi

while IFS= read -r ros_root; do
  if [ -d "$ros_root/share" ]; then
    run_timed "ROS2 runtime share deploy" deploy_ros_runtime_share_closure "$ros_root/share"
    break
  fi
done < <(emit_ros_root_candidates | sort -u)

run_timed "ROS2 root runtime lib deploy" copy_ros_root_runtime_libs
run_timed "system runtime lib deploy" copy_ldconfig_runtime_libs
run_timed "ros2cs metadata deploy" deploy_metadata_files

if [ -d "$installRoot/standalone" ] || [ -d "$installRoot/resources" ] || compgen -G "$installRoot/lib/librcl.so*" > /dev/null; then
  require_file_glob "rcl runtime" "${nativePluginDir}/librcl.so*"
  require_file_glob "class_loader runtime" "${nativePluginDir}/libclass_loader.so*"
  require_any_file_glob "Fast DDS/Fast RTPS runtime" "${nativePluginDir}/libfastdds.so*" "${nativePluginDir}/libfastrtps.so*"
  require_file_glob "rmw implementation runtime" "${nativePluginDir}/librmw_implementation.so*"
  require_any_file_glob "rcl logging runtime" "${nativePluginDir}/librcl_logging_implementation.so*" "${nativePluginDir}/librcl_logging_spdlog.so*" "${nativePluginDir}/librcl_logging_noop.so*"
  require_file_glob "rmw_implementation package index" "${nativePluginDir}/share/ament_index/resource_index/packages/rmw_implementation"
  require_file_glob "rmw_fastrtps_cpp typesupport index" "${nativePluginDir}/share/ament_index/resource_index/rmw_typesupport/rmw_fastrtps_cpp"
  require_file_glob "StreamingAssets rmw_implementation package index" "${streamingAssetsShareDestination}/ament_index/resource_index/packages/rmw_implementation"
  require_file_glob "StreamingAssets rmw_fastrtps_cpp typesupport index" "${streamingAssetsShareDestination}/ament_index/resource_index/rmw_typesupport/rmw_fastrtps_cpp"
  if compgen -G "${nativePluginDir}/librosidl_buffer_backend_registry.so*" > /dev/null; then
    require_file_glob "rosidl_buffer_backend package index" "${nativePluginDir}/share/ament_index/resource_index/packages/rosidl_buffer_backend"
    require_file_glob "StreamingAssets rosidl_buffer_backend package index" "${streamingAssetsShareDestination}/ament_index/resource_index/packages/rosidl_buffer_backend"
  fi
  if ! compgen -G "${nativePluginDir}/libyaml.so*" > /dev/null && ! compgen -G "${nativePluginDir}/libyaml-cpp.so*" > /dev/null; then
    echo "Required deployed YAML runtime is missing: expected libyaml.so* or libyaml-cpp.so* under ${nativePluginDir}/" >&2
    exit 1
  fi
fi

managed_count=$(find "${pluginDir}" -maxdepth 1 -type f | wc -l)
native_count=$(find "${nativePluginDir}/" -maxdepth 1 \( -type f -o -type l \) | wc -l)
echo "Deployment file counts: managed=${managed_count} native=${native_count}"
