$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Added fail-fast plugin deployment with an explicit install root.
# - Made optional standalone-library copies non-fatal when the source directory is absent.
# - Replaced PowerShell -Exclude directory filtering with explicit file-name predicates.

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$pluginDir = if ($args.Count -gt 0) { $args[0] } else { "" }
$installRoot = if ($args.Count -gt 1) { $args[1] } else { Join-Path -Path $scriptPath -ChildPath "install" }

function Print-Help {
"
Usage: 
deploy_unity_plugins.ps1 <PLUGINS_DIR> [INSTALL_ROOT]

PLUGINS_DIR - Ros2ForUnity/Plugins.
INSTALL_ROOT - ros2cs install prefix. Defaults to this repository's install directory.
"
}

if ($pluginDir -eq "--help" -Or $pluginDir -eq "-h")
{
    Print-Help
    exit 0
}

if ([string]::IsNullOrEmpty($pluginDir))
{
    Print-Help
    exit 1
}

if (Test-Path -Path $pluginDir) {
    Write-Host "Copying plugins to: '$pluginDir' ..."
    $dotnetDir = Join-Path -Path $installRoot -ChildPath "lib\dotnet"
    if (-not (Test-Path -LiteralPath $dotnetDir)) {
        throw "Managed plugin source directory does not exist: $dotnetDir"
    }
    Get-ChildItem -LiteralPath $dotnetDir -File |
        Where-Object { $_.Name -notlike "*.pdb" } |
        Copy-Item -Destination ${pluginDir} -Force

    Write-Host "Plugins copied to: '$pluginDir'" -ForegroundColor Green
    $windowsPluginDir = Join-Path -Path $pluginDir -ChildPath "Windows\x86_64"
    if(-not (Test-Path -LiteralPath $windowsPluginDir)) {
        New-Item -ItemType Directory -Force -Path $windowsPluginDir | Out-Null
    }
    Write-Host "Copying libraries to: '$windowsPluginDir' ..."
    $binDir = Join-Path -Path $installRoot -ChildPath "bin"
    if (-not (Test-Path -LiteralPath $binDir)) {
        throw "Native library source directory does not exist: $binDir"
    }
    Get-ChildItem -LiteralPath $binDir -File |
        Where-Object { $_.Name -notlike "*_py.dll" -and $_.Name -notlike "*_python.dll" } |
        Copy-Item -Destination $windowsPluginDir -Force

    # Standalone/resource outputs are optional; non-standalone builds must still deploy the core plugins.
    $standaloneDir = Join-Path -Path $installRoot -ChildPath "standalone"
    if(Test-Path -LiteralPath $standaloneDir) {
        Get-ChildItem -LiteralPath $standaloneDir -File -Filter "*.dll" |
            Copy-Item -Destination $windowsPluginDir -Force
    }
    $resourcesDir = Join-Path -Path $installRoot -ChildPath "resources"
    if(Test-Path -LiteralPath $resourcesDir) {
        Get-ChildItem -LiteralPath $resourcesDir -File -Filter "*.dll" |
            Copy-Item -Destination $windowsPluginDir -Force
    }
    Write-Host "Libraries copied to '$windowsPluginDir'" -ForegroundColor Green
} else {
    Write-Host "Plugins directory: '$pluginDir' doesn't exist. Please create it first manually." -ForegroundColor Red
    exit 1
}
