#!/bin/bash
# Copyright (c) 2026 Jianbin Liu.
#
# Purpose:
# - Added a Docker CI-candidate smoke check for R2FU Linux artifact closure.
# - Initialized the optional ROS setup trace variable before sourcing Jazzy under nounset.

set -euo pipefail

workspace="${1:-${R2FU_WORKDIR:-/workdir/ros2-for-unity}}"
asset_dir="$workspace/install/asset/Ros2ForUnity"
plugin_dir="$asset_dir/Plugins"
native_dir="$plugin_dir/Linux/x86_64"
ldd_log=$(mktemp "${TMPDIR:-/tmp}/r2fu-ci-smoke-ldd.XXXXXX")
topic_log=$(mktemp "${TMPDIR:-/tmp}/r2fu-ci-smoke-topic-list.XXXXXX")
managed_probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/r2fu-managed-probe.XXXXXX")
cleanup() {
  local status=$?
  if [ "$status" -eq 0 ]; then
    rm -f "$ldd_log" "$topic_log"
    rm -rf "$managed_probe_dir"
  else
    echo "Keeping smoke diagnostic logs: $ldd_log $topic_log" >&2
    echo "Keeping managed probe directory: $managed_probe_dir" >&2
  fi
}
trap cleanup EXIT

# ros:jazzy setup.bash reads this optional variable without a default under nounset.
: "${AMENT_TRACE_SETUP_FILES:=}"
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

require_glob "$native_dir/librcl.so*" >/dev/null
require_glob "$native_dir/librmw_implementation.so*" >/dev/null
require_glob "$native_dir/libyaml*.so*" >/dev/null

require_min_count() {
  local label="$1"
  local actual="$2"
  local minimum="$3"
  if ! [[ "$actual" =~ ^[0-9]+$ ]] || ! [[ "$minimum" =~ ^[0-9]+$ ]]; then
    echo "Invalid $label count check: actual='$actual' minimum='$minimum'" >&2
    exit 1
  fi
  if [ "$actual" -lt "$minimum" ]; then
    echo "$label count too low: $actual < $minimum" >&2
    exit 1
  fi
}

probe_managed_assemblies() {
  cat >"$managed_probe_dir/ManagedAssemblyProbe.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
EOF
  cat >"$managed_probe_dir/Program.cs" <<'EOF'
using System.Reflection;
using System.Runtime.Loader;

if (args.Length == 0)
{
    Console.Error.WriteLine("No managed assemblies were provided.");
    return 2;
}

string pluginDir = Path.GetDirectoryName(Path.GetFullPath(args[0])) ?? Directory.GetCurrentDirectory();
AssemblyLoadContext.Default.Resolving += (context, name) =>
{
    string candidate = Path.Combine(pluginDir, name.Name + ".dll");
    return File.Exists(candidate) ? context.LoadFromAssemblyPath(candidate) : null;
};

foreach (string assemblyPath in args)
{
    string fullPath = Path.GetFullPath(assemblyPath);
    Assembly assembly = AssemblyLoadContext.Default.LoadFromAssemblyPath(fullPath);
    Console.WriteLine("Loaded managed assembly: " + assembly.GetName().Name);
    foreach (AssemblyName reference in assembly.GetReferencedAssemblies())
    {
        AssemblyLoadContext.Default.LoadFromAssemblyName(reference);
    }
}

return 0;
EOF
  dotnet run --project "$managed_probe_dir" -- \
    "$plugin_dir/ros2cs_common.dll" \
    "$plugin_dir/ros2cs_core.dll"
}

managed_count=$(find "$plugin_dir" -maxdepth 1 -type f | wc -l)
native_count=$(find "$native_dir" -maxdepth 1 -type f | wc -l)
# Defaults match the expected Jazzy standalone artifact shape; override only when the package layout changes.
min_managed_count=${R2FU_DOCKER_MIN_MANAGED_FILES:-10}
min_native_count=${R2FU_DOCKER_MIN_NATIVE_FILES:-20}
ros_cli_timeout=${R2FU_DOCKER_ROS_CLI_TIMEOUT:-30s}
require_min_count "managed artifact" "$managed_count" "$min_managed_count"
require_min_count "native artifact" "$native_count" "$min_native_count"

echo "Checking managed assembly loadability."
probe_managed_assemblies

echo "Checking native dependency closure with ldd."
find "$native_dir" -maxdepth 1 -type f -name "*.so*" -print0 |
  sort -z |
  while IFS= read -r -d '' native_lib; do
    echo "==> $native_lib"
    ldd "$native_lib"
  done | tee "$ldd_log"
if grep -q "not found" "$ldd_log"; then
  echo "Native dependency closure has unresolved libraries." >&2
  echo "ldd log: $ldd_log" >&2
  exit 1
fi

echo "Checking ROS 2 CLI context availability."
# 30 s covers Fast DDS loopback discovery on cold CI runners; increase with R2FU_DOCKER_ROS_CLI_TIMEOUT if needed.
timeout "$ros_cli_timeout" ros2 topic list >"$topic_log"

# Linux/Jazzy artifact closure only. This does not validate Windows artifacts or Unity Editor/Player behavior.
echo "R2FU_DOCKER_CI_SMOKE_PASS distro=${ROS_DISTRO:-unset} platform=linux managed=$managed_count native=$native_count rmw=${RMW_IMPLEMENTATION:-unset} ldd_log=$ldd_log topic_log=$topic_log"
