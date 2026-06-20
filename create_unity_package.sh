#!/bin/bash
# Copyright (c) 2026 Jianbin Liu.
#
# Purpose:
# - Added strict/fail-fast Unity package creation.
# - Sanitized Unity-version-derived temporary paths before filesystem use.

set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

display_usage() {
  echo "This script creates a temporary Unity project in '/tmp' directory, copy input asset and makes an unity package out of it. Valid Unity license is required."
  echo ""
  echo "Usage:"
  echo "create_unity_package.sh -u <UNITY_PATH> -i [INPUT_ASSET] -p [PACKAGE_NAME] -o [OUTPUT_DIR] [--distro DISTRO] [--platform PLATFORM]"
  echo ""
  echo "UNITY_PATH - Unity editor executable path"
  echo "INPUT_ASSET - input asset to pack into unity package, default = '<script dir>/install/asset/Ros2ForUnity'"
  echo "PACKAGE_NAME - unity package name, default = 'Ros2ForUnity'"
  echo "OUTPUT_DIR - output file directory, default = 'install/unity_package'"
  echo "DISTRO - ROS 2 distro label for the output filename, default = ROS_DISTRO when set"
  echo "PLATFORM - platform label for the output filename, default = linux_x86_64"
}

UNITY_PATH=""
INPUT_ASSET="$SCRIPTPATH/install/asset/Ros2ForUnity"
PACKAGE_NAME="Ros2ForUnity"
OUTPUT_DIR="$SCRIPTPATH/install/unity_package"
DISTRO="${ROS_DISTRO:-}"
PLATFORM="linux_x86_64"

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -u|--unity-path)
      UNITY_PATH="$2"
      shift # past argument
      shift # past value
      ;;
    -p|--package_name)
      PACKAGE_NAME="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--input-directory)
      INPUT_ASSET="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--output-directory)
      OUTPUT_DIR="$2"
      shift # past argument
      shift # past value
      ;;
    --distro)
      DISTRO="$2"
      shift # past argument
      shift # past value
      ;;
    --platform)
      PLATFORM="$2"
      shift # past argument
      shift # past value
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

if [ -z "$UNITY_PATH" ] || [ -z "$PACKAGE_NAME" ] || [ -z "$INPUT_ASSET" ] || [ -z "$OUTPUT_DIR" ]; then
    echo -e "\nMissing arguments!"
    echo ""
    display_usage
    exit 1
fi

if [ ! -d "$INPUT_ASSET" ]; then
    echo "Input asset '$INPUT_ASSET' doesn't exist!  Use 'build.sh' to build project first."
    exit 1
fi

if [ ! -x "$UNITY_PATH" ]; then
    echo "Unity editor executable '$UNITY_PATH' does not exist or is not executable." >&2
    exit 1
fi

safe_name_part() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

join_package_name_parts() {
  local result=""
  local part
  local safe_part
  for part in "$@"; do
    if [ -z "$part" ]; then
      continue
    fi
    safe_part=$(safe_name_part "$part")
    if [ -z "$safe_part" ]; then
      continue
    fi
    if [ -z "$result" ]; then
      result="$safe_part"
    else
      result="${result}_${safe_part}"
    fi
  done
  printf '%s\n' "$result"
}

assert_project_sentinel() {
  [ -f "$1/ProjectSettings/ProjectVersion.txt" ]
}

assert_package_created() {
  local package_path="$1"
  if [ ! -f "$package_path" ]; then
    echo "Unity exited successfully but output package was not created: $package_path. Check Unity license." >&2
    return 1
  fi
  if [ ! -s "$package_path" ]; then
    echo "Unity output package is empty: $package_path. Check Unity license." >&2
    return 1
  fi
}

write_sha256_file() {
  local package_path="$1"
  local hash_file="${package_path}.sha256.txt"
  local file_name
  file_name=$(basename "$package_path")
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$package_path" | awk -v name="$file_name" '{ print $1 "  " name }' > "$hash_file"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$package_path" | awk -v name="$file_name" '{ print $1 "  " name }' > "$hash_file"
  else
    echo "Could not find sha256sum or shasum to write package checksum." >&2
    return 1
  fi
}

unity_version_from_path() {
  local path="$1"
  if [[ "$path" =~ /([0-9]{4}\.[0-9]+\.[0-9]+f?[0-9]*)/Editor/Unity$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

UNITY_VERSION=$(unity_version_from_path "$UNITY_PATH" || true)
if [ -z "$UNITY_VERSION" ]; then
  UNITY_VERSION=$("$UNITY_PATH" -version | head -n 1)
fi
SAFE_UNITY_VERSION=$(printf '%s' "$UNITY_VERSION" | tr -c 'A-Za-z0-9._-' '_')
if [ -z "$SAFE_UNITY_VERSION" ]; then
    echo "Cannot derive a safe Unity version path from '$UNITY_VERSION'."
    exit 1
fi

# Test if unity editor is valid
if [[ $UNITY_VERSION =~ ^[0-9]{4}\.[0-9]*\.[0-9]*f?[0-9]*$ ]]; then
    echo "Unity editor confirmed."
else
    while true; do
      read -p "Can't confirm Unity editor. Do you want to force \"$UNITY_PATH\" as an Unity editor executable? [y]es or [N]o: " yn
      yn=${yn:-"n"}
      case $yn in
          [Yy]* ) break;;
          [Nn]* ) exit 1;;
          * ) echo "Please answer [y]es or [n]o.";;
      esac
    done
fi

echo "Using \"${UNITY_PATH}\" editor."

TMP_ROOT="${TMPDIR:-/tmp}"
TMP_PROJECT_PATH="$TMP_ROOT/ros2cs_unity_project/$SAFE_UNITY_VERSION"
UNITY_LOG_DIR="$TMP_ROOT/ros2cs_unity_project_logs"
CREATE_PROJECT_LOG="$UNITY_LOG_DIR/create_$SAFE_UNITY_VERSION.log"
EXPORT_PACKAGE_LOG="$UNITY_LOG_DIR/export_$SAFE_UNITY_VERSION.log"
mkdir -p "$UNITY_LOG_DIR"
OUTPUT_PACKAGE_NAME=$(join_package_name_parts "$PACKAGE_NAME" "$DISTRO" "$PLATFORM")
if [ -z "$OUTPUT_PACKAGE_NAME" ]; then
    echo "Cannot derive output package name."
    exit 1
fi
OUTPUT_PACKAGE_PATH="$OUTPUT_DIR/$OUTPUT_PACKAGE_NAME.unitypackage"
# Create temp project
if [ -d "$TMP_PROJECT_PATH" ]; then
    if ! assert_project_sentinel "$TMP_PROJECT_PATH"; then
        echo "Existing temporary project for Unity $UNITY_VERSION is incomplete; recreating it."
        rm -rf "$TMP_PROJECT_PATH"
    fi
fi
if [ -d "$TMP_PROJECT_PATH" ]; then
    echo "Found existing temporary project for Unity $UNITY_VERSION."
    rm -rf "$TMP_PROJECT_PATH/Assets"
    mkdir -p "$TMP_PROJECT_PATH/Assets"
else
  echo "Creating Unity temporary project for Unity $UNITY_VERSION..."
  if ! "$UNITY_PATH" -createProject "$TMP_PROJECT_PATH" -batchmode -quit 2>&1 | tee "$CREATE_PROJECT_LOG"; then
    echo "Unity project creation failed. See log: $CREATE_PROJECT_LOG" >&2
    exit 1
  fi
  if ! assert_project_sentinel "$TMP_PROJECT_PATH"; then
    echo "Unity project creation completed but ProjectSettings/ProjectVersion.txt is missing. See log: $CREATE_PROJECT_LOG" >&2
    exit 1
  fi
fi

# Copy asset
echo "Copying asset to export..."
if command -v rsync >/dev/null 2>&1; then
  mkdir -p "$TMP_PROJECT_PATH/Assets/$PACKAGE_NAME"
  rsync --archive --delete "$INPUT_ASSET/" "$TMP_PROJECT_PATH/Assets/$PACKAGE_NAME/"
else
  rm -rf "$TMP_PROJECT_PATH/Assets/$PACKAGE_NAME"
  cp -r "$INPUT_ASSET" "$TMP_PROJECT_PATH/Assets/$PACKAGE_NAME"
fi

# Creating asset
echo "Saving unitypackage '$OUTPUT_PACKAGE_PATH'..."
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_PACKAGE_PATH"
if ! "$UNITY_PATH" -projectPath "$TMP_PROJECT_PATH" -exportPackage "Assets/$PACKAGE_NAME" "$OUTPUT_PACKAGE_PATH" -batchmode -quit 2>&1 | tee "$EXPORT_PACKAGE_LOG"; then
  echo "Unity package export failed. See log: $EXPORT_PACKAGE_LOG" >&2
  exit 1
fi
assert_package_created "$OUTPUT_PACKAGE_PATH"
write_sha256_file "$OUTPUT_PACKAGE_PATH"

# Cleaning up happens only after a successful export so failed runs keep logs and project state for diagnosis.
echo "Cleaning up temporary project..."
rm -rf "$TMP_PROJECT_PATH/Assets"
mkdir -p "$TMP_PROJECT_PATH/Assets"

echo "Done!"
