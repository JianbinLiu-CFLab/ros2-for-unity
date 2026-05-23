
<#
.SYNOPSIS
    Builds Ros2ForUnity asset
.DESCRIPTION
    This script builds Ros2DorUnity asset
.PARAMETER with_tests
    Build tests
.PARAMETER standalone
    Add ros2 binaries. Currently standalone flag is fixed to true, so there is no way to build without standalone libs. Parameter kept for future releases
.PARAMETER clean_install
    Makes a clean installation. Removes install dir before deploying
#>
Param (
    [Parameter(Mandatory=$false)][switch]$with_tests=$false,
    [Parameter(Mandatory=$false)][switch]$standalone=$false,
    [Parameter(Mandatory=$false)][switch]$clean_install=$false
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

if(-Not (Test-Path -Path "$scriptPath\src\ros2cs")) {
    Write-Host "Pull repositories with 'pull_repositories.ps1' first." -ForegroundColor Red
    exit 1
}

Write-Host "Building Ros2ForUnity asset..." -ForegroundColor Green
$tests_switch = if ($with_tests) { 1 } else { 0 }
$standalone_switch = if ($standalone) { 1 } else { 0 }

if($clean_install) {
    Write-Host "Cleaning install directory..." -ForegroundColor White
    Remove-Item -Path "$scriptPath\install" -Force -Recurse -ErrorAction Ignore
}

if($standalone) {
  & "python" "$scriptPath\src\scripts\metadata_generator.py" --standalone
} else {
  & "python" "$scriptPath\src\scripts\metadata_generator.py"
}
if ($LASTEXITCODE -ne 0) {
    throw "metadata_generator.py failed with exit code $LASTEXITCODE"
}

$ros2csItem = Get-Item "$scriptPath\src\ros2cs" -Force
$ros2csPath = if ($ros2csItem.Target -and $ros2csItem.Target.Count -gt 0) { $ros2csItem.Target[0] } else { $ros2csItem.FullName }
$ros2csSourcePath = Join-Path -Path $ros2csPath -ChildPath "src"
$ros2csInstallPath = Join-Path -Path $ros2csPath -ChildPath "install"
$ros2csBuildBase = if ([string]::IsNullOrEmpty($Env:R2FU_ROS2CS_BUILD_BASE)) { "D:\r2fu_b" } else { $Env:R2FU_ROS2CS_BUILD_BASE }
$ros2csLogBase = if ([string]::IsNullOrEmpty($Env:R2FU_ROS2CS_LOG_BASE)) { "D:\r2fu_l" } else { $Env:R2FU_ROS2CS_LOG_BASE }
$pythonExecutable = if ([string]::IsNullOrEmpty($Env:COLCON_PYTHON_EXECUTABLE)) { (Get-Command python).Source } else { $Env:COLCON_PYTHON_EXECUTABLE }
$colconExecutable = (Get-Command colcon).Source

Write-Host "Building ros2cs from '$ros2csPath' with Ninja/Release..." -ForegroundColor Green
& $colconExecutable `
    --log-base $ros2csLogBase `
    build `
    --base-paths $ros2csSourcePath `
    --build-base $ros2csBuildBase `
    --install-base $ros2csInstallPath `
    --merge-install `
    --event-handlers console_direct+ `
    --cmake-args `
    -G Ninja `
    -DSTANDALONE_BUILD:int=$standalone_switch `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_TESTING:int=$tests_switch `
    "-DPython3_EXECUTABLE:FILEPATH=$pythonExecutable" `
    --no-warn-unused-cli
if($LASTEXITCODE -eq 0) {
    md -Force $scriptPath\install\asset | Out-Null
    Copy-Item -Path $scriptPath\src\Ros2ForUnity -Destination $scriptPath\install\asset\ -Recurse -Force
    
    $plugin_path=Join-Path -Path $scriptPath -ChildPath "\install\asset\Ros2ForUnity\Plugins\"
    Write-Host "Deploying build to $plugin_path" -ForegroundColor Green
    & "$scriptPath\deploy_unity_plugins.ps1" $plugin_path $ros2csInstallPath
    if ($LASTEXITCODE -ne 0) {
        throw "deploy_unity_plugins.ps1 failed with exit code $LASTEXITCODE"
    }

    Copy-Item -Path $scriptPath\src\Ros2ForUnity\metadata_ros2cs.xml -Destination $scriptPath\install\asset\Ros2ForUnity\Plugins\Windows\x86_64\
    Copy-Item -Path $scriptPath\src\Ros2ForUnity\metadata_ros2cs.xml -Destination $scriptPath\install\asset\Ros2ForUnity\Plugins\
} else {
    Write-Host "Ros2cs build failed!" -ForegroundColor Red
    exit 1
}


