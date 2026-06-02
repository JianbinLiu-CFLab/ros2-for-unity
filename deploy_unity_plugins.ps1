# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Modifications by Jianbin Liu:
# - Added fail-fast plugin deployment with an explicit install root.
# - Made optional standalone-library copies non-fatal when the source directory is absent.
# - Replaced PowerShell -Exclude directory filtering with explicit file-name predicates.
# - Added deployment timing and required managed/native file checks.

Param (
    [Parameter(Mandatory=$false, Position=0)][string]$pluginDir = "",
    [Parameter(Mandatory=$false, Position=1)][string]$installRoot = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($installRoot)) {
    $installRoot = Join-Path -Path $scriptPath -ChildPath "install"
}
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
    Write-Host "Ros2ForUnity plugin deployment timing summary:" -ForegroundColor Cyan
    foreach ($row in $script:TimingRows) {
        Write-Host ("  {0,-28} {1}" -f $row.Phase, (Format-Duration $row.Elapsed))
    }
    Write-Host ("  {0,-28} {1}" -f "total", (Format-Duration $script:TotalStopwatch.Elapsed))
}

function Copy-FilesWithRobocopy {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [string[]]$Includes = @("*.*"),
        [string[]]$Excludes = @()
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Copy source directory does not exist: $Source"
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    $robocopyArgs = @($Source, $Destination)
    $robocopyArgs += $Includes
    if ($Excludes.Count -gt 0) {
        $robocopyArgs += "/XF"
        $robocopyArgs += $Excludes
    }
    $robocopyArgs += @("/R:2", "/W:1", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")

    & robocopy @robocopyArgs
    $robocopyExitCode = $LASTEXITCODE
    # Robocopy success/informational codes are 0-7.
    if ($robocopyExitCode -gt 7) {
        throw "robocopy failed from '$Source' to '$Destination' with exit code $robocopyExitCode"
    }
    $global:LASTEXITCODE = 0
}

function Assert-RequiredFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required deployed file is missing: $Path"
    }
}

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

try {
    if (Test-Path -LiteralPath $pluginDir) {
        Write-Host "Copying plugins to: '$pluginDir' ..."
        $dotnetDir = Join-Path -Path $installRoot -ChildPath "lib\dotnet"
        if (-not (Test-Path -LiteralPath $dotnetDir)) {
            throw "Managed plugin source directory does not exist: $dotnetDir"
        }
        Invoke-Timed "managed DLL deploy" {
            Copy-FilesWithRobocopy -Source $dotnetDir -Destination $pluginDir -Includes @("*.*") -Excludes @("*.pdb")
        }
        Assert-RequiredFile (Join-Path -Path $pluginDir -ChildPath "ros2cs_common.dll")
        Assert-RequiredFile (Join-Path -Path $pluginDir -ChildPath "ros2cs_core.dll")

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
        Invoke-Timed "native bin DLL deploy" {
            Copy-FilesWithRobocopy -Source $binDir -Destination $windowsPluginDir -Includes @("*.*") -Excludes @("*_py.dll", "*_python.dll")
        }

        # Standalone/resource outputs are optional; non-standalone builds must still deploy the core plugins.
        $standaloneDir = Join-Path -Path $installRoot -ChildPath "standalone"
        $hasStandaloneDir = Test-Path -LiteralPath $standaloneDir
        if($hasStandaloneDir) {
            Invoke-Timed "standalone DLL deploy" {
                Copy-FilesWithRobocopy -Source $standaloneDir -Destination $windowsPluginDir -Includes @("*.dll")
            }
        }
        $resourcesDir = Join-Path -Path $installRoot -ChildPath "resources"
        $hasResourcesDir = Test-Path -LiteralPath $resourcesDir
        if($hasResourcesDir) {
            Invoke-Timed "resource DLL deploy" {
                Copy-FilesWithRobocopy -Source $resourcesDir -Destination $windowsPluginDir -Includes @("*.dll")
            }
        }

        if ($hasStandaloneDir -or $hasResourcesDir -or (Test-Path -LiteralPath (Join-Path -Path $binDir -ChildPath "rcl.dll"))) {
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "rcl.dll")
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "rmw_implementation.dll")
            $yamlDll = Join-Path -Path $windowsPluginDir -ChildPath "yaml.dll"
            $yamlCppDll = Join-Path -Path $windowsPluginDir -ChildPath "yaml-cpp.dll"
            if (-not ((Test-Path -LiteralPath $yamlDll) -or (Test-Path -LiteralPath $yamlCppDll))) {
                throw "Required deployed YAML runtime is missing: expected yaml.dll or yaml-cpp.dll under $windowsPluginDir"
            }
        }

        $managedCount = (Get-ChildItem -LiteralPath $pluginDir -File | Measure-Object).Count
        $nativeCount = (Get-ChildItem -LiteralPath $windowsPluginDir -File | Measure-Object).Count
        Write-Host "Libraries copied to '$windowsPluginDir'" -ForegroundColor Green
        Write-Host "Deployment file counts: managed=$managedCount native=$nativeCount" -ForegroundColor Green
    } else {
        throw "Plugins directory: '$pluginDir' doesn't exist. Please create it first manually."
    }
}
finally {
    Write-TimingSummary
}
