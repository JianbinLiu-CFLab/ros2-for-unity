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
    $robocopyArgs = @($Source, $Destination)
    $robocopyArgs += $Includes
    if ($Excludes.Count -gt 0) {
        $robocopyArgs += "/XF"
        $robocopyArgs += $Excludes
    }
    $robocopyArgs += @("/R:1", "/W:0", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")

    & robocopy @robocopyArgs
    $robocopyExitCode = $LASTEXITCODE
    # Robocopy success/informational codes are 0-7.
    if ($robocopyExitCode -gt 7) {
        throw "robocopy failed from '$Source' to '$Destination' with exit code $robocopyExitCode"
    }
    $global:LASTEXITCODE = 0
}

function Copy-DirectoryTreeWithRobocopy {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Copy source directory does not exist: $Source"
    }

    & robocopy $Source $Destination /E /R:1 /W:0 /NP /NFL /NDL /NJH /NJS
    $robocopyExitCode = $LASTEXITCODE
    # Robocopy success/informational codes are 0-7.
    if ($robocopyExitCode -gt 7) {
        throw "robocopy failed from '$Source' to '$Destination' with exit code $robocopyExitCode"
    }
    $global:LASTEXITCODE = 0
}

function Copy-FilePreservingRelativePath {
    param(
        [Parameter(Mandatory=$true)][string]$SourceRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][string]$RelativePath
    )

    $source = Join-Path -Path $SourceRoot -ChildPath $RelativePath
    if (-not (Test-Path -LiteralPath $source)) {
        return
    }

    $destination = Join-Path -Path $DestinationRoot -ChildPath $RelativePath
    $destinationDir = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Copy-RosRuntimeShareClosure {
    param(
        [Parameter(Mandatory=$true)][string]$SourceShare,
        [Parameter(Mandatory=$true)][string]$DestinationShare
    )

    $runtimePackages = @(
        "ament_index_cpp",
        "fastcdr",
        "fastdds",
        "foonathan_memory_vendor",
        "rcpputils",
        "rcutils",
        "rmw",
        "rmw_dds_common",
        "rmw_fastrtps_cpp",
        "rmw_fastrtps_shared_cpp",
        "rmw_implementation",
        "rmw_implementation_cmake",
        "rmw_security_common",
        "rosidl_buffer_backend",
        "rosidl_dynamic_typesupport",
        "rosidl_dynamic_typesupport_fastrtps",
        "rosidl_runtime_c",
        "rosidl_runtime_cpp",
        "rosidl_typesupport_c",
        "rosidl_typesupport_cpp",
        "rosidl_typesupport_fastrtps_c",
        "rosidl_typesupport_fastrtps_cpp",
        "rosidl_typesupport_introspection_c",
        "rosidl_typesupport_introspection_cpp"
    )
    $resourceIndexes = @(
        "packages",
        "package_run_dependencies",
        "parent_prefix_path",
        "rmw_output_patterns",
        "rmw_output_prefixes",
        "rmw_typesupport",
        "rmw_typesupport_c",
        "rmw_typesupport_cpp",
        "rosidl_typesupport_c",
        "rosidl_typesupport_cpp"
    )

    foreach ($packageName in $runtimePackages) {
        foreach ($resourceIndex in $resourceIndexes) {
            Copy-FilePreservingRelativePath `
                -SourceRoot $SourceShare `
                -DestinationRoot $DestinationShare `
                -RelativePath (Join-Path -Path "ament_index\resource_index\$resourceIndex" -ChildPath $packageName)
        }
    }
}

function Assert-RequiredFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required deployed file is missing: $Path"
    }
}

function Find-RosRuntimeDll {
    param([Parameter(Mandatory=$true)][string]$FileName)

    $candidateDirs = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:ROS2_ROOT)) {
        $candidateDirs.Add((Join-Path -Path $env:ROS2_ROOT -ChildPath "bin")) | Out-Null
    }
    foreach ($pathDir in ($env:PATH -split [System.IO.Path]::PathSeparator)) {
        if (-not [string]::IsNullOrWhiteSpace($pathDir)) {
            $candidateDirs.Add($pathDir) | Out-Null
        }
    }

    foreach ($dir in ($candidateDirs | Select-Object -Unique)) {
        $candidate = Join-Path -Path $dir -ChildPath $FileName
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Find-RosRootCandidates {
    $roots = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:ROS2_ROOT)) {
        $roots.Add($env:ROS2_ROOT) | Out-Null
    }

    foreach ($pathDir in ($env:PATH -split [System.IO.Path]::PathSeparator)) {
        if ([string]::IsNullOrWhiteSpace($pathDir)) {
            continue
        }
        if ((Split-Path -Leaf $pathDir) -ne "bin") {
            continue
        }

        $root = Split-Path -Parent $pathDir
        if (Test-Path -LiteralPath (Join-Path -Path $root -ChildPath "share\ament_index")) {
            $roots.Add($root) | Out-Null
        }
    }

    return $roots | Select-Object -Unique
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

        $assetRoot = Split-Path -Parent $pluginDir
        $shareDestination = Join-Path -Path $windowsPluginDir -ChildPath "share"
        foreach ($ros2Root in Find-RosRootCandidates) {
            $ros2Share = Join-Path -Path $ros2Root -ChildPath "share"
            if (Test-Path -LiteralPath $ros2Share) {
                Invoke-Timed "ROS2 runtime share deploy" {
                    Copy-RosRuntimeShareClosure -SourceShare $ros2Share -DestinationShare $shareDestination
                }
                break
            }
        }

        $rosRootRuntimeDlls = @(
            "class_loader.dll",
            "fastdds-3.6.dll",
            "rcl_logging_implementation.dll",
            "rosidl_buffer_backend_registry.dll"
        )
        $rosRootRuntimeSources = @()
        foreach ($dllName in $rosRootRuntimeDlls) {
            $runtimeDll = Find-RosRuntimeDll $dllName
            if ($null -ne $runtimeDll) {
                $rosRootRuntimeSources += $runtimeDll
            }
        }
        if ($rosRootRuntimeSources.Count -gt 0) {
            Invoke-Timed "ROS2 root runtime DLL deploy" {
                foreach ($runtimeDll in $rosRootRuntimeSources) {
                    Copy-Item -LiteralPath $runtimeDll -Destination $windowsPluginDir -Force
                }
            }
        }

        if ($hasStandaloneDir -or $hasResourcesDir -or (Test-Path -LiteralPath (Join-Path -Path $binDir -ChildPath "rcl.dll"))) {
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "rcl.dll")
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "class_loader.dll")
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "fastdds-3.6.dll")
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "rmw_implementation.dll")
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "rosidl_buffer_backend_registry.dll")
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "rcl_logging_implementation.dll")
            Assert-RequiredFile (Join-Path -Path $shareDestination -ChildPath "ament_index\resource_index\packages\rosidl_buffer_backend")
            Assert-RequiredFile (Join-Path -Path $shareDestination -ChildPath "ament_index\resource_index\packages\rmw_implementation")
            Assert-RequiredFile (Join-Path -Path $shareDestination -ChildPath "ament_index\resource_index\rmw_typesupport\rmw_fastrtps_cpp")
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
