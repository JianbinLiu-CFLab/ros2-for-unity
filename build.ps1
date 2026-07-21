
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
    Makes a clean installation. Removes R2FU install plus ros2cs build/install/log roots before deploying.
.PARAMETER quiet
    Reduce live colcon console output. Full logs are still written under the configured colcon log base.
.PARAMETER console_direct
    Preserve the chatty console_direct+ colcon output. This is the default for compatibility.
.PARAMETER strict_pin
    Fail when the local src\ros2cs checkout does not match ros2cs.repos. By default this is a warning.

Copyright (c) 2026 Jianbin Liu.

Purpose:
- Added strict/fail-fast behavior for Windows builds.
- Routed ros2cs builds through the canonical ros2cs workspace with short build roots.
- Preserved standalone asset deployment as the public Windows packaging path.
- Added phase timing, quiet/verbose output control, and robocopy-based asset staging.
- Bound colcon and Ninja parallelism through ROS2CS_PARALLEL_WORKERS for stable parallel Windows release builds.
#>
Param (
    [Parameter(Mandatory=$false)][switch]$with_tests=$false,
    [Parameter(Mandatory=$false)][switch]$standalone=$false,
    [Parameter(Mandatory=$false)][switch]$clean_install=$false,
    [Parameter(Mandatory=$false)][switch]$quiet=$false,
    [Parameter(Mandatory=$false)][switch]$console_direct=$false,
    [Parameter(Mandatory=$false)][switch]$strict_pin=$false
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
    # Mirror the Unity asset tree with robocopy while normalizing robocopy's non-error success codes.
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
        # Eight worker threads keeps local staging fast without overwhelming smaller developer machines.
        "/MT:8",
        # Retry twice with a one-second wait so transient file locks fail quickly during CI/local packaging.
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
    # Put default short work roots at the drive root to keep generated ROS/MSVC paths under Windows limits.
    param([Parameter(Mandatory=$true)][string]$Name)
    $driveRoot = [System.IO.Path]::GetPathRoot($scriptPath)
    if ([string]::IsNullOrEmpty($driveRoot))
    {
        $driveRoot = [System.IO.Path]::GetPathRoot((Get-Location).Path)
    }
    return Join-Path -Path $driveRoot -ChildPath $Name
}

function Resolve-RequiredCommand {
    # Resolve tool paths early so missing ROS/Python tooling fails before the long colcon build.
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

function Resolve-Ros2csParallelWorkers {
    # Keep one colcon package active while this value bounds native compiler jobs inside Ninja.
    if ([string]::IsNullOrWhiteSpace($Env:ROS2CS_PARALLEL_WORKERS)) {
        return [Math]::Max(1, [System.Environment]::ProcessorCount)
    }

    [int]$workers = 0
    if (-not [int]::TryParse($Env:ROS2CS_PARALLEL_WORKERS, [ref]$workers) -or $workers -lt 1) {
        throw "ROS2CS_PARALLEL_WORKERS must be a positive integer when set."
    }
    return $workers
}

function Remove-DirectoryIfPresent {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Refusing to remove empty $Description path."
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrEmpty($root) -or ($fullPath.TrimEnd('\') -eq $root.TrimEnd('\'))) {
        throw "Refusing to remove unsafe $Description path: $fullPath"
    }

    if (Test-Path -LiteralPath $fullPath) {
        Write-Host "Removing ${Description}: $fullPath" -ForegroundColor White
        Remove-Item -LiteralPath $fullPath -Force -Recurse -ErrorAction Stop
    }
}

function Get-PinnedRos2csCommit {
    param([Parameter(Mandatory=$true)][string]$ReposPath)

    $reposText = Get-Content -LiteralPath $ReposPath -Raw
    if ($reposText -match '(?ms)src/ros2cs/:\s*.*?^\s+version:\s*([0-9a-fA-F]{40})\s*$') {
        return $matches[1].ToLowerInvariant()
    }
    throw "Could not find a pinned 40-character ros2cs commit in $ReposPath"
}

function Assert-Ros2csPin {
    param(
        [Parameter(Mandatory=$true)][string]$Ros2csPath,
        [Parameter(Mandatory=$true)][string]$ReposPath,
        [Parameter(Mandatory=$true)][bool]$Strict
    )

    $expectedCommit = Get-PinnedRos2csCommit -ReposPath $ReposPath
    $actualCommit = $null
    try {
        $actualCommit = (& git -C $Ros2csPath rev-parse HEAD 2>$null).Trim().ToLowerInvariant()
    } catch {
        # Handled below with a consistent warning/error message.
    }

    if ([string]::IsNullOrEmpty($actualCommit)) {
        $message = "Could not read src\ros2cs git HEAD; expected ros2cs.repos pin $expectedCommit."
        if ($Strict) { throw $message }
        Write-Warning $message
        return
    }

    if ($actualCommit -ne $expectedCommit) {
        $message = "src\ros2cs HEAD $actualCommit does not match ros2cs.repos pin $expectedCommit."
        if ($Strict) { throw $message }
        Write-Warning $message
    }
}

function Write-LatestColconLogTail {
    param([Parameter(Mandatory=$true)][string]$LogBase)

    if (-not (Test-Path -LiteralPath $LogBase)) {
        return
    }

    $latestLog = Get-ChildItem -LiteralPath $LogBase -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".log", ".txt") } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $latestLog) {
        return
    }

    Write-Warning "Latest colcon log tail: $($latestLog.FullName)"
    Get-Content -LiteralPath $latestLog.FullName -Tail 80 | ForEach-Object {
        Write-Host $_ -ForegroundColor DarkGray
    }
}

try {
    if(-Not (Test-Path -LiteralPath "$scriptPath\src\ros2cs")) {
        throw "Pull repositories with 'pull_repositories.ps1' first."
    }

    if ([string]::IsNullOrEmpty($Env:ROS_DISTRO)) {
        throw "Can't detect ROS2 version. Source your ROS 2 distro first."
    }

    Write-Host "Building Ros2ForUnity asset..." -ForegroundColor Green
    $tests_switch = if ($with_tests) { 1 } else { 0 }
    $standalone_switch = if ($standalone) { 1 } else { 0 }

    # Resolve the junction target so colcon builds the canonical ros2cs workspace, not the R2FU src wrapper.
    $ros2csItem = Get-Item "$scriptPath\src\ros2cs" -Force
    $ros2csPath = if ($ros2csItem.Target -and $ros2csItem.Target.Count -gt 0) { $ros2csItem.Target[0] } else { $ros2csItem.FullName }
    $ros2csSourcePath = Join-Path -Path $ros2csPath -ChildPath "src"
    # R2FU_ROS2CS_* overrides let outer validation scripts share or isolate ros2cs build/install/log roots.
    $ros2csInstallPath = if ([string]::IsNullOrEmpty($Env:R2FU_ROS2CS_INSTALL_BASE)) {
        Join-Path -Path $ros2csPath -ChildPath "install"
    } else { $Env:R2FU_ROS2CS_INSTALL_BASE }
    # Keep generated ROS/MSVC object paths short while allowing CI or local scripts to override the roots.
    $ros2csBuildBase = if ([string]::IsNullOrEmpty($Env:R2FU_ROS2CS_BUILD_BASE)) { Get-DefaultWorkPath "r2fu_b" } else { $Env:R2FU_ROS2CS_BUILD_BASE }
    $ros2csLogBase = if ([string]::IsNullOrEmpty($Env:R2FU_ROS2CS_LOG_BASE)) { Get-DefaultWorkPath "r2fu_l" } else { $Env:R2FU_ROS2CS_LOG_BASE }
    Assert-Ros2csPin -Ros2csPath $ros2csPath -ReposPath (Join-Path -Path $scriptPath -ChildPath "ros2cs.repos") -Strict ([bool]$strict_pin)

    if($clean_install) {
        Invoke-Timed "clean install" {
            Remove-DirectoryIfPresent -Path (Join-Path -Path $scriptPath -ChildPath "install") -Description "R2FU install directory"
            Remove-DirectoryIfPresent -Path $ros2csBuildBase -Description "ros2cs build base"
            Remove-DirectoryIfPresent -Path $ros2csLogBase -Description "ros2cs log base"
            Remove-DirectoryIfPresent -Path $ros2csInstallPath -Description "ros2cs install base"
        }
    }

    Invoke-Timed "metadata generation" {
        if($standalone) {
          & "python" "$scriptPath\src\scripts\metadata_generator.py" --standalone --ros2cs-path $ros2csPath
        } else {
          & "python" "$scriptPath\src\scripts\metadata_generator.py" --ros2cs-path $ros2csPath
        }
        if ($LASTEXITCODE -ne 0) {
            throw "metadata_generator.py failed with exit code $LASTEXITCODE"
        }
    }

    $pythonExecutable = if ([string]::IsNullOrEmpty($Env:COLCON_PYTHON_EXECUTABLE)) {
        Resolve-RequiredCommand "python" "Run this script from a sourced ROS 2 environment, or set COLCON_PYTHON_EXECUTABLE."
    } else { $Env:COLCON_PYTHON_EXECUTABLE }
    $colconExecutable = Resolve-RequiredCommand "colcon" "Run this script from a sourced ROS 2 environment so colcon is on PATH."
    $ros2csParallelWorkers = Resolve-Ros2csParallelWorkers

    $ros2csPackageTargets = @(
        "ros2cs_tests",
        "ros2cs_examples",
        "std_msgs",
        "std_srvs",
        "rosgraph_msgs",
        "builtin_interfaces",
        "unique_identifier_msgs",
        "action_msgs",
        "example_interfaces",
        "test_msgs",
        "geometry_msgs",
        "sensor_msgs",
        "nav_msgs",
        "diagnostic_msgs",
        "statistics_msgs",
        "shape_msgs",
        "trajectory_msgs",
        "tf2",
        "tf2_msgs",
        "tf2_ros",
        "visualization_msgs",
        "composition_interfaces",
        "lifecycle_msgs",
        "stereo_msgs"
    )

    $availableRos2csPackages = & $colconExecutable list --base-paths $ros2csSourcePath --names-only
    if ($LASTEXITCODE -ne 0) {
        throw "colcon list failed while checking ros2cs package availability."
    }
    foreach ($optionalPackage in @(
        "actionlib_msgs",
        "service_msgs",
        "type_description_interfaces"
    )) {
        if ($availableRos2csPackages -contains $optionalPackage) {
            $ros2csPackageTargets += $optionalPackage
        }
    }

    $colconArgs = @(
        "--log-base", $ros2csLogBase,
        "build",
        "--base-paths", $ros2csSourcePath,
        "--build-base", $ros2csBuildBase,
        "--install-base", $ros2csInstallPath,
        "--merge-install",
        # Serial package scheduling prevents colcon package workers and Ninja jobs from multiplying.
        "--parallel-workers", "1",
        "--packages-up-to"
    )
    $colconArgs += $ros2csPackageTargets
    if ($console_direct -or -not $quiet) {
        $colconArgs += @("--event-handlers", "console_direct+")
    }
    $colconArgs += @(
        "--packages-skip",
        "rosidl_dynamic_typesupport_fastrtps",
        "rosidl_generator_py"
    )
    $colconArgs += @(
        "--cmake-args",
        "-G", "Ninja",
        "-DSTANDALONE_BUILD:int=$standalone_switch",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DBUILD_TESTING:int=$tests_switch",
        "-DPython3_EXECUTABLE:FILEPATH=$pythonExecutable",
        "--no-warn-unused-cli"
    )

    Write-Host "Building ros2cs from '$ros2csPath' with Ninja/Release (one package, $ros2csParallelWorkers native jobs)..." -ForegroundColor Green
    if ($quiet -and -not $console_direct) {
        Write-Host "Quiet mode: colcon console_direct+ is disabled; inspect logs under '$ros2csLogBase' on failure." -ForegroundColor Yellow
    }

    $previousMakeflags = $env:MAKEFLAGS
    try {
        # colcon_cmake forwards MAKEFLAGS to CMake/Ninja; restore the caller's value after this build.
        $env:MAKEFLAGS = "-j$ros2csParallelWorkers -l$ros2csParallelWorkers"
        Invoke-Timed "ros2cs colcon build" {
            & $colconExecutable @colconArgs
            if($LASTEXITCODE -ne 0) {
                Write-LatestColconLogTail -LogBase $ros2csLogBase
                throw "Ros2cs build failed with exit code $LASTEXITCODE"
            }
        }
    } finally {
        if ($null -eq $previousMakeflags) {
            Remove-Item Env:MAKEFLAGS -ErrorAction SilentlyContinue
        } else {
            $env:MAKEFLAGS = $previousMakeflags
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
        if($standalone) {
          & "python" "$scriptPath\src\scripts\metadata_generator.py" --standalone --ros2cs-path $ros2csPath --plugins-dir $pluginPath
        } else {
          & "python" "$scriptPath\src\scripts\metadata_generator.py" --ros2cs-path $ros2csPath --plugins-dir $pluginPath
        }
        if ($LASTEXITCODE -ne 0) {
            throw "metadata_generator.py failed with exit code $LASTEXITCODE"
        }
        $metadataSource = Join-Path -Path $scriptPath -ChildPath "src\Ros2ForUnity\metadata_ros2cs.xml"
        $metadataWindowsDestination = Join-Path -Path $scriptPath -ChildPath "install\asset\Ros2ForUnity\Plugins\Windows\x86_64"
        $metadataPluginDestination = Join-Path -Path $scriptPath -ChildPath "install\asset\Ros2ForUnity\Plugins"
        # Keep one metadata copy beside platform native DLLs and one at Plugins root for platform-agnostic readers.
        Copy-Item -LiteralPath $metadataSource -Destination $metadataWindowsDestination -Force
        Copy-Item -LiteralPath $metadataSource -Destination $metadataPluginDestination -Force
    }
}
finally {
    Write-TimingSummary
}


