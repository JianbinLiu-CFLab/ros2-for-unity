
<#
.SYNOPSIS
    Builds Ros2ForUnity asset
.DESCRIPTION
    This script builds Ros2ForUnity asset
.PARAMETER with_tests
    Build tests
.PARAMETER standalone
    Add ros2 binaries. Currently standalone flag is fixed to true, so there is no way to build without standalone libs. Parameter kept for future releases
.PARAMETER clean_install
    Makes a clean installation. Removes install dir before deploying
.PARAMETER quiet
    Reduce live colcon console output. Full logs are still written under the configured colcon log base.
.PARAMETER console_direct
    Preserve the chatty console_direct+ colcon output. This is the default for compatibility.

Modifications Copyright (c) 2026 Jianbin Liu.

Modifications by Jianbin Liu:
- Added strict/fail-fast behavior for Windows builds.
- Routed ros2cs builds through the canonical ros2cs workspace with short build roots.
- Preserved standalone asset deployment as the public Windows packaging path.
- Added phase timing, quiet/verbose output control, and robocopy-based asset staging.
#>
Param (
    [Parameter(Mandatory=$false)][switch]$with_tests=$false,
    [Parameter(Mandatory=$false)][switch]$standalone=$false,
    [Parameter(Mandatory=$false)][switch]$clean_install=$false,
    [Parameter(Mandatory=$false)][switch]$quiet=$false,
    [Parameter(Mandatory=$false)][switch]$console_direct=$false
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:TimingRows = New-Object System.Collections.Generic.List[object]
$script:TotalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Format-Duration {
    param([Parameter(Mandatory=$true)][TimeSpan]$Elapsed)
    return "{0:mm\:ss\.fff}" -f $Elapsed
}

function Invoke-Timed {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Action
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action
    }
    finally {
        $watch.Stop()
        $script:TimingRows.Add([pscustomobject]@{
            Phase = $Name
            Elapsed = $watch.Elapsed
        }) | Out-Null
    }
}

function Write-TimingSummary {
    if ($script:TotalStopwatch.IsRunning) {
        $script:TotalStopwatch.Stop()
    }

    Write-Host ""
    Write-Host "Ros2ForUnity build timing summary:" -ForegroundColor Cyan
    foreach ($row in $script:TimingRows) {
        Write-Host ("  {0,-28} {1}" -f $row.Phase, (Format-Duration $row.Elapsed))
    }
    Write-Host ("  {0,-28} {1}" -f "total", (Format-Duration $script:TotalStopwatch.Elapsed))
}

function Invoke-RobocopyMirror {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "robocopy source does not exist: $Source"
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $robocopyArgs = @(
        $Source,
        $Destination,
        "/MIR",
        "/MT:8",
        "/R:2",
        "/W:1",
        "/NP"
    )
    if ($quiet -and -not $console_direct) {
        $robocopyArgs += @("/NFL", "/NDL")
    }

    & robocopy @robocopyArgs
    $robocopyExitCode = $LASTEXITCODE
    # Robocopy uses 0-7 for success / informational outcomes.
    if ($robocopyExitCode -gt 7) {
        throw "robocopy failed from '$Source' to '$Destination' with exit code $robocopyExitCode"
    }
    $global:LASTEXITCODE = 0
}

function Get-DefaultWorkPath {
    param([Parameter(Mandatory=$true)][string]$Name)
    $driveRoot = [System.IO.Path]::GetPathRoot($scriptPath)
    if ([string]::IsNullOrEmpty($driveRoot))
    {
        $driveRoot = [System.IO.Path]::GetPathRoot((Get-Location).Path)
    }
    return Join-Path -Path $driveRoot -ChildPath $Name
}

function Resolve-RequiredCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Hint
    )

    try {
        return (Get-Command $Name -ErrorAction Stop).Source
    } catch {
        throw "Required command '$Name' was not found. $Hint"
    }
}

try {
    if(-Not (Test-Path -LiteralPath "$scriptPath\src\ros2cs")) {
        throw "Pull repositories with 'pull_repositories.ps1' first."
    }

    Write-Host "Building Ros2ForUnity asset..." -ForegroundColor Green
    $tests_switch = if ($with_tests) { 1 } else { 0 }
    $standalone_switch = if ($standalone) { 1 } else { 0 }

    if($clean_install) {
        Invoke-Timed "clean install" {
            Write-Host "Cleaning install directory..." -ForegroundColor White
            Remove-Item -Path "$scriptPath\install" -Force -Recurse -ErrorAction Ignore
        }
    }

    Invoke-Timed "metadata generation" {
        if($standalone) {
          & "python" "$scriptPath\src\scripts\metadata_generator.py" --standalone
        } else {
          & "python" "$scriptPath\src\scripts\metadata_generator.py"
        }
        if ($LASTEXITCODE -ne 0) {
            throw "metadata_generator.py failed with exit code $LASTEXITCODE"
        }
    }

    # Resolve the junction target so colcon builds the canonical ros2cs workspace, not the R2FU src wrapper.
    $ros2csItem = Get-Item "$scriptPath\src\ros2cs" -Force
    $ros2csPath = if ($ros2csItem.Target -and $ros2csItem.Target.Count -gt 0) { $ros2csItem.Target[0] } else { $ros2csItem.FullName }
    $ros2csSourcePath = Join-Path -Path $ros2csPath -ChildPath "src"
    $ros2csInstallPath = Join-Path -Path $ros2csPath -ChildPath "install"
    # Keep generated ROS/MSVC object paths short while allowing CI or local scripts to override the roots.
    $ros2csBuildBase = if ([string]::IsNullOrEmpty($Env:R2FU_ROS2CS_BUILD_BASE)) { Get-DefaultWorkPath "r2fu_b" } else { $Env:R2FU_ROS2CS_BUILD_BASE }
    $ros2csLogBase = if ([string]::IsNullOrEmpty($Env:R2FU_ROS2CS_LOG_BASE)) { Get-DefaultWorkPath "r2fu_l" } else { $Env:R2FU_ROS2CS_LOG_BASE }
    $pythonExecutable = if ([string]::IsNullOrEmpty($Env:COLCON_PYTHON_EXECUTABLE)) {
        Resolve-RequiredCommand "python" "Run this script from a sourced ROS 2 Jazzy environment, or set COLCON_PYTHON_EXECUTABLE."
    } else { $Env:COLCON_PYTHON_EXECUTABLE }
    $colconExecutable = Resolve-RequiredCommand "colcon" "Run this script from a sourced ROS 2 Jazzy environment so colcon is on PATH."

    $colconArgs = @(
        "--log-base", $ros2csLogBase,
        "build",
        "--base-paths", $ros2csSourcePath,
        "--build-base", $ros2csBuildBase,
        "--install-base", $ros2csInstallPath,
        "--merge-install"
    )
    if ($console_direct -or -not $quiet) {
        $colconArgs += @("--event-handlers", "console_direct+")
    }
    $colconArgs += @(
        "--cmake-args",
        "-G", "Ninja",
        "-DSTANDALONE_BUILD:int=$standalone_switch",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_TESTING:int=$tests_switch",
        "-DPython3_EXECUTABLE:FILEPATH=$pythonExecutable",
        "--no-warn-unused-cli"
    )

    Write-Host "Building ros2cs from '$ros2csPath' with Ninja/Release..." -ForegroundColor Green
    if ($quiet -and -not $console_direct) {
        Write-Host "Quiet mode: colcon console_direct+ is disabled; inspect logs under '$ros2csLogBase' on failure." -ForegroundColor Yellow
    }

    Invoke-Timed "ros2cs colcon build" {
        & $colconExecutable @colconArgs
        if($LASTEXITCODE -ne 0) {
            throw "Ros2cs build failed with exit code $LASTEXITCODE"
        }
    }

    $assetRoot = Join-Path -Path $scriptPath -ChildPath "install\asset"
    $assetSource = Join-Path -Path $scriptPath -ChildPath "src\Ros2ForUnity"
    $assetDestination = Join-Path -Path $assetRoot -ChildPath "Ros2ForUnity"
    Invoke-Timed "Unity asset staging" {
        Invoke-RobocopyMirror -Source $assetSource -Destination $assetDestination
    }
    
    $pluginPath = Join-Path -Path $assetDestination -ChildPath "Plugins"
    Write-Host "Deploying build to $pluginPath" -ForegroundColor Green
    Invoke-Timed "plugin deploy" {
        & "$scriptPath\deploy_unity_plugins.ps1" $pluginPath $ros2csInstallPath
        if ($LASTEXITCODE -ne 0) {
            throw "deploy_unity_plugins.ps1 failed with exit code $LASTEXITCODE"
        }
    }

    Invoke-Timed "metadata copy" {
        $metadataSource = Join-Path -Path $scriptPath -ChildPath "src\Ros2ForUnity\metadata_ros2cs.xml"
        $metadataWindowsDestination = Join-Path -Path $scriptPath -ChildPath "install\asset\Ros2ForUnity\Plugins\Windows\x86_64"
        $metadataPluginDestination = Join-Path -Path $scriptPath -ChildPath "install\asset\Ros2ForUnity\Plugins"
        Copy-Item -LiteralPath $metadataSource -Destination $metadataWindowsDestination -Force
        Copy-Item -LiteralPath $metadataSource -Destination $metadataPluginDestination -Force
    }
}
finally {
    Write-TimingSummary
}


