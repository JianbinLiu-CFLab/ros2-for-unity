$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Updated supported ROS distribution messaging for Humble/Jazzy maintenance.
# - Made repository imports run from the repository root instead of the caller's current directory.

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

if (([string]::IsNullOrEmpty($Env:ROS_DISTRO)))
{
    Write-Host "Can't detect ROS2 version. Source your ROS 2 distro first. Humble and Jazzy are the maintained targets; Foxy/Galactic are historical." -ForegroundColor Red
    exit 1
}

$ros2cs_repos = Join-Path -Path $scriptPath -ChildPath "ros2cs.repos"
$custom_repos = Join-Path -Path $scriptPath -ChildPath "ros2_for_unity_custom_messages.repos"

# Anchor vcs imports at the repository root so callers can run this script from any CWD.
Push-Location $scriptPath
try {
    Write-Host "========================================="
    Write-Host "* Pulling ros2cs repository:"
    vcs import --input $ros2cs_repos
    if ($LASTEXITCODE -ne 0) { throw "vcs import ros2cs.repos failed with exit code $LASTEXITCODE" }

    Write-Host ""
    Write-Host "========================================="
    Write-Host "Pulling custom repositories:"
    vcs import --input $custom_repos
    if ($LASTEXITCODE -ne 0) { throw "vcs import custom messages failed with exit code $LASTEXITCODE" }

    Write-Host ""
    Write-Host "========================================="
    Write-Host "Pulling ros2cs dependencies:"
    & "$scriptPath/src/ros2cs/get_repos.ps1"
    if ($LASTEXITCODE -ne 0) { throw "ros2cs get_repos.ps1 failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
