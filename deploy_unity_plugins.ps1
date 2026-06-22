# Copyright (c) 2026 Jianbin Liu.
#
# Purpose:
# - Added fail-fast plugin deployment with an explicit install root.
# - Made optional standalone-library copies non-fatal when the source directory is absent.
# - Replaced PowerShell -Exclude directory filtering with explicit file-name predicates.
# - Added deployment timing and required managed/native file checks.

Param (
    [Parameter(Mandatory=$false, Position=0)][string]$pluginDir = "",
    [Parameter(Mandatory=$false, Position=1)][string]$installRoot = "",
    [Parameter(Mandatory=$false)][switch]$help=$false
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
    # Copy retries are deliberately short: CI/local artifact builds should fail fast on persistent locks.
    $robocopyArgs += @("/R:1", "/W:0", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")

    & robocopy @robocopyArgs
    $robocopyExitCode = $LASTEXITCODE
    # Robocopy success/informational codes are 0-7.
    if ($robocopyExitCode -gt 7) {
        throw "robocopy failed from '$Source' to '$Destination' with exit code $robocopyExitCode"
    }
    $global:LASTEXITCODE = 0
}

function Remove-DeployedPluginOutputs {
    param(
        [Parameter(Mandatory=$true)][string]$PluginDir,
        [Parameter(Mandatory=$true)][string]$NativePluginDir,
        [Parameter(Mandatory=$true)][string]$StreamingAssetsShareDestination
    )

    if (Test-Path -LiteralPath $NativePluginDir) {
        Remove-Item -LiteralPath $NativePluginDir -Recurse -Force
    }

    if (Test-Path -LiteralPath $StreamingAssetsShareDestination) {
        Remove-Item -LiteralPath $StreamingAssetsShareDestination -Recurse -Force
    }

    Get-ChildItem -LiteralPath $PluginDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq ".dll" -or $_.Name -eq "metadata_ros2cs.xml" } |
        Remove-Item -Force
}

function Copy-MetadataFile {
    param(
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$Description
    )

    $metadataSource = Join-Path -Path $scriptPath -ChildPath "src\Ros2ForUnity\metadata_ros2cs.xml"
    if (-not (Test-Path -LiteralPath $metadataSource)) {
        throw "metadata_ros2cs.xml source file is missing: $metadataSource"
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -LiteralPath $metadataSource -Destination $Destination -Force
    Assert-RequiredFile (Join-Path -Path $Destination -ChildPath "metadata_ros2cs.xml")
    Write-Host "Copied ros2cs metadata to $Description" -ForegroundColor Green
}

function Copy-FilePreservingRelativePath {
    # Copy selected ament-index files without materializing the entire ROS 2 share tree.
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
    # Deploy the minimum ament-index closure required for ROS 2 runtime discovery inside Unity players.
    param(
        [Parameter(Mandatory=$true)][string]$SourceShare,
        [Parameter(Mandatory=$true)][string]$DestinationShare
    )

    # These package entries cover RMW selection, typesupport lookup, and dynamic type backend discovery.
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
        "rmw_zenoh_cpp",
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
    # Resource indexes are copied package-by-package to avoid pulling large unrelated share directories.
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

    # rmw_zenoh_cpp resolves its session/router config from share\rmw_zenoh_cpp\config at runtime
    # (FastRTPS needs no such file). These live outside ament_index, so copy them explicitly. The
    # copy helper early-returns on missing sources, so distros without rmw_zenoh (Jazzy) are unaffected.
    foreach ($zenohConfig in @(
        "rmw_zenoh_cpp\config\DEFAULT_RMW_ZENOH_SESSION_CONFIG.json5",
        "rmw_zenoh_cpp\config\DEFAULT_RMW_ZENOH_ROUTER_CONFIG.json5"
    )) {
        Copy-FilePreservingRelativePath `
            -SourceRoot $SourceShare `
            -DestinationRoot $DestinationShare `
            -RelativePath $zenohConfig
    }
}

function Assert-RequiredFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required deployed file is missing: $Path"
    }
}

function Assert-RequiredFileGlob {
    param(
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][string]$Pattern
    )
    if ($null -eq (Get-ChildItem -Path $Pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        throw "Required deployed $Description is missing: expected $Pattern"
    }
}

function Assert-RequiredFileGlobAny {
    param(
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($null -ne (Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            return
        }
    }

    throw "Required deployed $Description is missing: expected one of $($Patterns -join ', ')"
}

function Get-RosRuntimeSearchDirs {
    # Prefer explicit ROS2_ROOT/bin, then fall back to PATH entries from the sourced ROS environment.
    $candidateDirs = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:ROS2_ROOT)) {
        $candidateDirs.Add((Join-Path -Path $env:ROS2_ROOT -ChildPath "bin")) | Out-Null
    }
    foreach ($pathDir in ($env:PATH -split [System.IO.Path]::PathSeparator)) {
        if (-not [string]::IsNullOrWhiteSpace($pathDir)) {
            $candidateDirs.Add($pathDir) | Out-Null
        }
    }

    return $candidateDirs | Select-Object -Unique
}

function Find-RosRuntimeDlls {
    # Locate runtime DLLs that live in the active ROS root rather than the ros2cs install prefix.
    param([Parameter(Mandatory=$true)][string]$Pattern)

    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($dir in Get-RosRuntimeSearchDirs) {
        Get-ChildItem -LiteralPath $dir -Filter $Pattern -File -ErrorAction SilentlyContinue |
            ForEach-Object { $matches.Add($_.FullName) | Out-Null }
    }

    return $matches | Select-Object -Unique
}

function Find-RosRootCandidates {
    # Infer ROS roots from ROS2_ROOT and PATH/bin entries that contain an ament index.
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

if ($help -or $pluginDir -eq "--help" -Or $pluginDir -eq "-h")
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
        $windowsPluginDir = Join-Path -Path $pluginDir -ChildPath "Windows\x86_64"
        $assetRoot = Split-Path -Parent $pluginDir
        $shareDestination = Join-Path -Path $windowsPluginDir -ChildPath "share"
        $assetInstallRoot = Split-Path -Parent $assetRoot
        $legacyNestedStreamingAssets = Join-Path -Path $assetRoot -ChildPath "StreamingAssets"
        $streamingAssetsShareDestination = Join-Path -Path $assetInstallRoot -ChildPath "StreamingAssets\Ros2ForUnity\share"

        Invoke-Timed "stale plugin cleanup" {
            Remove-DeployedPluginOutputs `
                -PluginDir $pluginDir `
                -NativePluginDir $windowsPluginDir `
                -StreamingAssetsShareDestination $streamingAssetsShareDestination
            # Remove the old nested asset-local StreamingAssets shape; current builds use install/asset/StreamingAssets.
            if (Test-Path -LiteralPath $legacyNestedStreamingAssets) {
                Remove-Item -LiteralPath $legacyNestedStreamingAssets -Recurse -Force
            }
        }

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

        foreach ($ros2Root in Find-RosRootCandidates) {
            $ros2Share = Join-Path -Path $ros2Root -ChildPath "share"
            if (Test-Path -LiteralPath $ros2Share) {
                Invoke-Timed "ROS2 runtime share deploy" {
                    Copy-RosRuntimeShareClosure -SourceShare $ros2Share -DestinationShare $shareDestination
                    Copy-RosRuntimeShareClosure -SourceShare $ros2Share -DestinationShare $streamingAssetsShareDestination
                }
                break
            }
        }

        # These DLLs are resolved from the active ROS root/PATH. Jazzy still ships Fast RTPS
        # as fastrtps-*.dll, while Lyrical ships Fast DDS as fastdds-*.dll.
        $rosRootRuntimeDllPatterns = @(
            "class_loader.dll",
            "fastdds*.dll",
            "fastrtps*.dll",
            "rcl_logging_implementation.dll",
            "rcl_logging_interface.dll",
            "rcl_logging_noop.dll",
            "rcl_logging_spdlog.dll",
            "rosidl_buffer_backend_registry.dll"
        )
        $rosRootRuntimeSources = @()
        $runtimeSearchDirs = @(Get-RosRuntimeSearchDirs)
        foreach ($dllPattern in $rosRootRuntimeDllPatterns) {
            $runtimeDlls = @(Find-RosRuntimeDlls $dllPattern)
            if ($runtimeDlls.Count -eq 0) {
                Write-Warning "Could not find required ROS2 runtime DLL pattern '$dllPattern'. Searched: $($runtimeSearchDirs -join '; ')"
            } else {
                $rosRootRuntimeSources += $runtimeDlls
            }
        }
        if ($rosRootRuntimeSources.Count -gt 0) {
            Invoke-Timed "ROS2 root runtime DLL deploy" {
                foreach ($runtimeDll in $rosRootRuntimeSources) {
                    Copy-Item -LiteralPath $runtimeDll -Destination $windowsPluginDir -Force
                }
            }
        }

        Invoke-Timed "ros2cs metadata deploy" {
            # Keep metadata next to native Windows DLLs and at Plugins root for platform-agnostic runtime readers.
            Copy-MetadataFile -Destination $pluginDir -Description "Plugins root"
            Copy-MetadataFile -Destination $windowsPluginDir -Description "Windows/x86_64 plugin directory"
        }

        if ($hasStandaloneDir -or $hasResourcesDir -or (Test-Path -LiteralPath (Join-Path -Path $binDir -ChildPath "rcl.dll"))) {
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "rcl.dll")
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "class_loader.dll")
            Assert-RequiredFileGlobAny -Description "Fast DDS/Fast RTPS runtime" -Patterns @(
                (Join-Path -Path $windowsPluginDir -ChildPath "fastdds*.dll"),
                (Join-Path -Path $windowsPluginDir -ChildPath "fastrtps*.dll")
            )
            Assert-RequiredFile (Join-Path -Path $windowsPluginDir -ChildPath "rmw_implementation.dll")
            Assert-RequiredFileGlobAny -Description "rcl logging runtime" -Patterns @(
                (Join-Path -Path $windowsPluginDir -ChildPath "rcl_logging_implementation.dll"),
                (Join-Path -Path $windowsPluginDir -ChildPath "rcl_logging_spdlog.dll"),
                (Join-Path -Path $windowsPluginDir -ChildPath "rcl_logging_noop.dll")
            )
            Assert-RequiredFile (Join-Path -Path $shareDestination -ChildPath "ament_index\resource_index\packages\rmw_implementation")
            Assert-RequiredFile (Join-Path -Path $shareDestination -ChildPath "ament_index\resource_index\rmw_typesupport\rmw_fastrtps_cpp")
            Assert-RequiredFile (Join-Path -Path $streamingAssetsShareDestination -ChildPath "ament_index\resource_index\packages\rmw_implementation")
            Assert-RequiredFile (Join-Path -Path $streamingAssetsShareDestination -ChildPath "ament_index\resource_index\rmw_typesupport\rmw_fastrtps_cpp")
            if (Test-Path -LiteralPath (Join-Path -Path $windowsPluginDir -ChildPath "rosidl_buffer_backend_registry.dll")) {
                Assert-RequiredFile (Join-Path -Path $shareDestination -ChildPath "ament_index\resource_index\packages\rosidl_buffer_backend")
                Assert-RequiredFile (Join-Path -Path $streamingAssetsShareDestination -ChildPath "ament_index\resource_index\packages\rosidl_buffer_backend")
            }
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
