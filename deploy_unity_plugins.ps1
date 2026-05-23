$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

if (([string]::IsNullOrEmpty($pluginDir)) -Or $pluginDir -eq "--help" -Or $pluginDir -eq "-h")
{
    Print-Help
    exit 1
}

if (Test-Path -Path $pluginDir) {
    Write-Host "Copying plugins to to: '$pluginDir' ..."
    Get-ChildItem "$installRoot\lib\dotnet\" -Recurse -Exclude @('*.pdb') | Copy-Item -Destination ${pluginDir}
    Write-Host "Plugins copied to: '$pluginDir'" -ForegroundColor Green
    if(-not (Test-Path -Path $pluginDir\Windows\x86_64\)) {
        mkdir ${pluginDir}\Windows\x86_64\
    }
    Write-Host "Copying libraries to: '$pluginDir\Windows\x86_64\' ..."
    Get-ChildItem "$installRoot\bin\" -Recurse -Exclude @('*_py.dll', '*_python.dll') | Copy-Item -Destination ${pluginDir}\Windows\x86_64\
    if(Test-Path -Path "$installRoot\standalone\") {
        Copy-Item -Path "$installRoot\standalone\*.dll" -Destination "${pluginDir}\Windows\x86_64\" -ErrorAction SilentlyContinue
    }
    if(Test-Path -Path "$installRoot\resources\") {
        Copy-Item -Path "$installRoot\resources\*.dll" -Destination "${pluginDir}\Windows\x86_64\" -ErrorAction SilentlyContinue
    }
    Write-Host "Libraries copied to '${pluginDir}\Windows\x86_64\'" -ForegroundColor Green
} else {
    Write-Host "Plugins directory: '$pluginDir' doesn't exist. Please create it first manually." -ForegroundColor Red
    exit 1
}
