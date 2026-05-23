#!/bin/bash
set -euo pipefail

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage:" 
  echo "deploy_unity_plugins.sh <PLUGINS_DIR>"
  echo ""
  echo "PLUGINS_DIR - Ros2ForUnity/Plugins folder."
  exit 1
fi

pluginDir=$1

mkdir -p "${pluginDir}/Linux/x86_64/"
find "$SCRIPTPATH/install/lib/dotnet/" -maxdepth 1 -not -name "*.pdb" -type f -exec cp {} "${pluginDir}" \;
if [ -d "$SCRIPTPATH/install/standalone" ]; then
  find "$SCRIPTPATH/install/standalone" -maxdepth 1 \( -type f -o -type l \) -exec cp -L {} "${pluginDir}/Linux/x86_64/" \;
fi
find "$SCRIPTPATH/install/lib/" -maxdepth 1 \( -type f -o -type l \) -not -name "*_python.so" -exec cp -L {} "${pluginDir}/Linux/x86_64/" \;
if [ -d "$SCRIPTPATH/install/resources" ]; then
  find "$SCRIPTPATH/install/resources" -maxdepth 1 -name "*.so" \( -type f -o -type l \) -exec cp -L {} "${pluginDir}/Linux/x86_64/" \;
fi
