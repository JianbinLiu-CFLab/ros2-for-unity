
<#
.SYNOPSIS
    Creates a 'unitypackage' from an input asset.
.DESCRIPTION
    This script creates a temporary Unity project in "%USERPROFILE%\AppData\Local\Temp" directory, copies the input asset, and makes a unity package out of it. Valid Unity license is required.
.PARAMETER unity_path
    Unity editor executable path
.PARAMETER input_asset
    input asset to pack into unity package
.PARAMETER package_name
    Unity package name
.PARAMETER output_dir
    output file directory
.PARAMETER distro
    ROS 2 distro label for the output package filename. Defaults to ROS_DISTRO when set.
.PARAMETER platform
    Platform label for the output package filename.

Copyright (c) 2026 Jianbin Liu.

Purpose:
- Added strict/fail-fast Unity package creation.
- Sanitized Unity-version-derived temporary paths before filesystem use.
#>
Param (
    [Parameter(Mandatory=$true)][string]$unity_path,
    [Parameter(Mandatory=$false)][string]$input_asset,
    [Parameter(Mandatory=$false)][string]$package_name="Ros2ForUnity",
    [Parameter(Mandatory=$false)][string]$output_dir,
    [Parameter(Mandatory=$false)][string]$distro=$Env:ROS_DISTRO,
    [Parameter(Mandatory=$false)][string]$platform="windows_x86_64"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$temp_dir = $Env:TEMP

if(-Not $PSBoundParameters.ContainsKey('input_asset')) {
    $input_asset= Join-Path -Path $scriptPath -ChildPath "install\asset\Ros2ForUnity"
}

if(-Not $PSBoundParameters.ContainsKey('output_dir')) {
    $output_dir= Join-Path -Path $scriptPath -ChildPath "install\unity_package"
}

if(-Not (Test-Path -LiteralPath "$input_asset" -PathType Container)) {
    Write-Host "Input asset '$input_asset' doesn't exist! Use 'build.ps1' to build project first." -ForegroundColor Red
    exit 1
}

if(-Not (Test-Path -LiteralPath "$output_dir")) {
    New-Item -ItemType Directory -Force -Path $output_dir | Out-Null
}

if (-Not (Test-Path -LiteralPath "$unity_path")) {
    throw "Unity editor executable '$unity_path' does not exist."
}

function Join-PackageNameParts {
    param([string[]]$Parts)
    $safeParts = @()
    foreach ($part in $Parts) {
        if ([string]::IsNullOrWhiteSpace($part)) {
            continue
        }
        $safe = $part -replace '[^A-Za-z0-9._-]', '_'
        if (-not [string]::IsNullOrWhiteSpace($safe)) {
            $safeParts += $safe
        }
    }
    return ($safeParts -join "_")
}

function Assert-ProjectSentinel {
    param([Parameter(Mandatory=$true)][string]$ProjectPath)
    return (Test-Path -LiteralPath (Join-Path -Path $ProjectPath -ChildPath "ProjectSettings\ProjectVersion.txt") -PathType Leaf)
}

function Assert-PackageCreated {
    param([Parameter(Mandatory=$true)][string]$PackagePath)
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw "Unity exited successfully but output package was not created: $PackagePath. Check Unity license."
    }
    if ((Get-Item -LiteralPath $PackagePath).Length -le 0) {
        throw "Unity output package is empty: $PackagePath. Check Unity license."
    }
}

function Write-Sha256File {
    param([Parameter(Mandatory=$true)][string]$PackagePath)
    $hash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashFile = "$PackagePath.sha256.txt"
    $fileName = Split-Path -Leaf $PackagePath
    Set-Content -LiteralPath $hashFile -Value "$hash  $fileName" -Encoding ASCII
}

function Get-UnityVersionFromPath {
    param([Parameter(Mandatory=$true)][string]$UnityPath)
    $normalizedPath = $UnityPath -replace '/', '\'
    if ($normalizedPath -match '\\(?<version>[0-9]{4}\.[0-9]+\.[0-9]+f?[0-9]*)\\Editor\\Unity(?:\.exe)?$') {
        return $Matches['version']
    }
    return $null
}

$unity_version = Get-UnityVersionFromPath -UnityPath $unity_path
if ([string]::IsNullOrEmpty($unity_version)) {
    $unityVersionOutput = & "$unity_path" -version
    if ($LASTEXITCODE -ne 0) {
        throw "Unity editor version check failed with exit code $LASTEXITCODE"
    }
    $unity_version = ($unityVersionOutput | Select-Object -First 1).Trim()
}

function Mirror-Directory {
    # Mirror the asset into Unity's temporary project and fail fast on persistent file locks.
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    & robocopy $Source $Destination /MIR /R:1 /W:0 /NP /NFL /NDL /NJH /NJS
    $robocopyExitCode = $LASTEXITCODE
    if ($robocopyExitCode -gt 7) {
        throw "robocopy failed from '$Source' to '$Destination' with exit code $robocopyExitCode"
    }
    $global:LASTEXITCODE = 0
}

if ($unity_version -match '^[0-9]{4}\.[0-9]*\.[0-9]*[f]?[0-9]*$') {
    Write-Host "Unity editor confirmed."
} else {
    while ($true) {
        $confirmation = Read-Host "Can't confirm Unity editor. Do you want to force $unity_path as an Unity editor executable? [y]es or [n]o"
        if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
            break;
        } elseif ( $confirmation -eq 'n' -or $confirmation -eq 'N' ) {
            exit 1;
        } else {
            Write-Host "Please answer [y]es or [n]o.";
        }
    }
}
Write-Host "Using ${unity_path} editor."

$safe_unity_version = $unity_version -replace '[^A-Za-z0-9._-]', '_'
if ([string]::IsNullOrEmpty($safe_unity_version)) {
    throw "Cannot derive a safe Unity version path from '$unity_version'."
}
$tmp_project_path = Join-Path -Path "$temp_dir" -ChildPath "ros2cs_unity_project\$safe_unity_version"
$unityLogDir = Join-Path -Path "$temp_dir" -ChildPath "ros2cs_unity_project_logs"
New-Item -ItemType Directory -Force -Path $unityLogDir | Out-Null
$createProjectLog = Join-Path -Path $unityLogDir -ChildPath "create_$safe_unity_version.log"
$exportPackageLog = Join-Path -Path $unityLogDir -ChildPath "export_$safe_unity_version.log"
$assetsPath = Join-Path -Path $tmp_project_path -ChildPath "Assets"
$output_package_name = Join-PackageNameParts @($package_name, $distro, $platform)
if ([string]::IsNullOrWhiteSpace($output_package_name)) {
    throw "Cannot derive output package name."
}
$outputPackagePath = Join-Path -Path $output_dir -ChildPath "$output_package_name.unitypackage"

# Create temp project
if(Test-Path -LiteralPath "$tmp_project_path") {
    if (-not (Assert-ProjectSentinel -ProjectPath $tmp_project_path)) {
        Write-Host "Existing temporary project for Unity $unity_version is incomplete; recreating it."
        Remove-Item -LiteralPath $tmp_project_path -Force -Recurse -ErrorAction Ignore
    }
}
if(Test-Path -LiteralPath "$tmp_project_path") {
    Write-Host "Found existing temporary project for Unity $unity_version."
    Remove-Item -LiteralPath $assetsPath -Force -Recurse -ErrorAction Ignore
    New-Item -ItemType Directory -Force -Path $assetsPath | Out-Null
} else {
    Write-Host "Creating Unity temporary project for Unity $unity_version..."
    & "$unity_path" -createProject "$tmp_project_path" -batchmode -quit 2>&1 | Tee-Object -FilePath $createProjectLog | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unity project creation failed with exit code $LASTEXITCODE. See log: $createProjectLog"
    }
    if (-not (Assert-ProjectSentinel -ProjectPath $tmp_project_path)) {
        throw "Unity project creation completed but ProjectSettings\ProjectVersion.txt is missing. See log: $createProjectLog"
    }
}

# Copy asset
Write-Host "Copying asset '$input_asset' to export..."
Mirror-Directory -Source "$input_asset" -Destination (Join-Path -Path $assetsPath -ChildPath $package_name)

# Creating asset
Write-Host "Saving unitypackage '$outputPackagePath'..."
if (Test-Path -LiteralPath $outputPackagePath) {
    Remove-Item -LiteralPath $outputPackagePath -Force
}
& "$unity_path" -projectPath "$tmp_project_path" -exportPackage "Assets\$package_name" "$outputPackagePath" -batchmode -quit 2>&1 | Tee-Object -FilePath $exportPackageLog | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Unity package export failed with exit code $LASTEXITCODE. See log: $exportPackageLog"
}
Assert-PackageCreated -PackagePath $outputPackagePath
Write-Sha256File -PackagePath $outputPackagePath

# Cleaning up happens only after a successful export so failed runs keep logs and project state for diagnosis.
Write-Host "Cleaning up temporary project..."
Remove-Item -LiteralPath $assetsPath -Force -Recurse -ErrorAction Ignore
New-Item -ItemType Directory -Force -Path $assetsPath | Out-Null

Write-Host "Done!" -ForegroundColor Green

