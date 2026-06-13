#!/bin/bash
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Added strict/fail-fast Unity package creation.
# - Sanitized Unity-version-derived temporary paths before filesystem use.

set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

display_usage() {
  echo "This script creates a temporary Unity project in '/tmp' directory, copy input asset and makes an unity package out of it. Valid Unity license is required."
  echo ""
  echo "Usage:"
  echo "create_unity_package.sh -u <UNITY_PATH> -i [INPUT_ASSET] -p [PACKAGE_NAME] -o [OUTPUT_DIR]"
  echo ""
  echo "UNITY_PATH - Unity editor executable path"
  echo "INPUT_ASSET - input asset to pack into unity package, default = '<script dir>/install/asset/Ros2ForUnity'"
  echo "PACKAGE_NAME - unity package name, default = 'Ros2ForUnity'"
  echo "OUTPUT_DIR - output file directory, default = 'install/unity_package'"
}

UNITY_PATH=""
INPUT_ASSET="$SCRIPTPATH/install/asset/Ros2ForUnity"
PACKAGE_NAME="Ros2ForUnity"
OUTPUT_DIR="$SCRIPTPATH/install/unity_package"

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

UNITY_VERSION=$("$UNITY_PATH" -version | head -n 1)
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
# Create temp project
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
fi

# Copy asset
echo "Copying asset to export..."
cp -r "$INPUT_ASSET" "$TMP_PROJECT_PATH/Assets/$PACKAGE_NAME"

# Creating asset
echo "Saving unitypackage '$OUTPUT_DIR/$PACKAGE_NAME.unitypackage'..."
mkdir -p "$OUTPUT_DIR"
if ! "$UNITY_PATH" -projectPath "$TMP_PROJECT_PATH" -exportPackage "Assets/$PACKAGE_NAME" "$OUTPUT_DIR/$PACKAGE_NAME.unitypackage" -batchmode -quit 2>&1 | tee "$EXPORT_PACKAGE_LOG"; then
  echo "Unity package export failed. See log: $EXPORT_PACKAGE_LOG" >&2
  exit 1
fi

# Cleaning up
echo "Cleaning up temporary project..."
rm -rf "$TMP_PROJECT_PATH/Assets"
mkdir -p "$TMP_PROJECT_PATH/Assets"

echo "Done!"
