<#
.SYNOPSIS
    One-shot build for the Windows 10 Mobile Moonlight UWP app.

.PARAMETER Clean
    Remove dependency/build caches before building. Keeps vcpkg\downloads\tools.

.PARAMETER CertificateThumbprint
    Thumbprint of the signing certificate. Defaults to the local test identity.

.EXAMPLE
    .\build-w10m.ps1 -Clean

.EXAMPLE
    .\build-w10m.ps1 -CertificateThumbprint 33D115B6B7BA9FF297ABFBB7497BF3E3C83B73F8
#>
[CmdletBinding()]
param(
    [switch]$Clean,
    [string]$CertificateThumbprint = '33D115B6B7BA9FF297ABFBB7497BF3E3C83B73F8',
    [string]$VsInstallPath = '',
    [string]$BuildTreesRoot = 'C:\Temp\w10m-vcpkg-buildtrees'
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$LogDir = Join-Path $Root 'build-logs'
$Log = Join-Path $LogDir ('build-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Remove-Item $Log -Force -ErrorAction SilentlyContinue

function Write-Log([string]$Message) {
    Write-Host $Message
    $Message | Out-File -FilePath $Log -Append -Encoding utf8
}

function Fail([string]$Message) {
    Write-Log "FAIL: $Message"
    Write-Host "::error::$Message"
    Get-Content $Log -Tail 120
    throw $Message
}

function Invoke-Checked([string]$Command, [string]$What) {
    Write-Log "=== $What ==="
    $safe = ($What -replace '[^A-Za-z0-9_.-]', '_')
    $rawLog = Join-Path $LogDir "$safe.raw.log"
    Remove-Item $rawLog -Force -ErrorAction SilentlyContinue
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        cmd /c "$Command > `"$rawLog`" 2>&1"
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    if (Test-Path $rawLog) {
        Get-Content $rawLog -Raw | Out-File -FilePath $Log -Append -Encoding utf8
    }
    Write-Log "exit=$code"
    if ($code -ne 0) {
        if (Test-Path $rawLog) {
            Get-Content $rawLog -Tail 30 | ForEach-Object { Write-Host "::error::$_" }
        }
        Fail "$What failed (exit $code)"
    }
}

if (-not $VsInstallPath) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $VsInstallPath = & $vswhere -latest -products * -property installationPath
    }
}
if (-not $VsInstallPath) {
    $VsInstallPath = Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\Community'
}
$VsDevCmd = Join-Path $VsInstallPath 'Common7\Tools\VsDevCmd.bat'
$MSBuild = Join-Path $VsInstallPath 'MSBuild\Current\Bin\MSBuild.exe'
$VCToolsRoot = Get-ChildItem (Join-Path $VsInstallPath 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $VCToolsRoot) { throw "MSVC tools not found under $VsInstallPath" }
$VCToolsLib = Join-Path $VCToolsRoot.FullName 'lib\arm'
if (-not (Test-Path $VCToolsLib)) { throw "ARM MSVC libraries not found: $VCToolsLib" }
cmd /c "subst V: `"$($VCToolsRoot.FullName)`"" 2>$null
if (-not (Test-Path $VsDevCmd)) { throw "VsDevCmd not found: $VsDevCmd" }

# VsDevCmd -winsdk is not always honored when several SDKs are installed.
# Pin the SDK tools explicitly so Ninja picks the 15063 rc.exe/mt.exe.
$SdkBin = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.15063.0\x64'
if (-not (Test-Path (Join-Path $SdkBin 'rc.exe'))) {
    throw "Windows SDK 15063 tools not found: $SdkBin"
}
# Linker flags cannot carry paths with spaces reliably through vcpkg.
# Expose the SDK on a space-free drive letter for this build session.
cmd /c "subst W: `"C:\Program Files (x86)\Windows Kits\10`"" 2>$null
$env:PATH = "W:\bin\10.0.15063.0\x64;$env:PATH"
$env:WindowsSDKVersion = '10.0.15063.0\'
$env:WindowsSdkDir = 'C:\Program Files (x86)\Windows Kits\10\'
$env:WindowsSdkBinPath = "$SdkBin\"
$env:WindowsSdkVerBinPath = "$SdkBin\"
$env:RC = Join-Path $SdkBin 'rc.exe'
$env:MT = Join-Path $SdkBin 'mt.exe'
if (-not (Test-Path $MSBuild)) { throw "MSBuild not found: $MSBuild" }

# Keep MSBuild's temporary files out of a possibly restricted user TEMP.
$BuildTemp = Join-Path $Root 'build-tmp'
New-Item -ItemType Directory -Force -Path $BuildTemp | Out-Null
$env:TMP = $BuildTemp
$env:TEMP = $BuildTemp
New-Item -ItemType Directory -Force -Path $BuildTreesRoot | Out-Null

Set-Location $Root

if ($Clean) {
    Write-Log '=== clean dependency/build caches (keep vcpkg tools) ==='
    foreach ($Path in @(
        'vcpkg_installed',
        'vcpkg\installed',
        'vcpkg\packages',
        'vcpkg\buildtrees',
        'third_party\moonlight-common-c\build',
        'libgamestream\build',
        'ARM'
    )) {
        Remove-Item (Join-Path $Root $Path) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item (Join-Path $env:LOCALAPPDATA 'vcpkg\archives') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $BuildTreesRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $BuildTreesRoot | Out-Null
}

# The script must not rely on an already-patched submodule working tree.
Invoke-Checked "`"$Root\apply-submodule-patches.cmd`"" 'apply submodule patches'

if (-not (Test-Path (Join-Path $Root 'vcpkg\vcpkg.exe'))) {
    Invoke-Checked "`"$Root\vcpkg\bootstrap-vcpkg.bat`"" 'bootstrap vcpkg'
}

# VsDevCmd may select a newer SDK when several are installed, so re-pin
# the SDK tools and library/include paths after calling it. Use a batch file
# so %LIB%/%INCLUDE%/%PATH% expand after VsDevCmd has updated the environment.
$VcpkgScript = Join-Path $BuildTemp 'run-vcpkg.cmd'
$VcpkgLines = @(
    '@echo off',
    "call `"$VsDevCmd`" -arch=arm -host_arch=x64 -winsdk=10.0.15063.0",
    'set "WindowsSDKVersion=10.0.15063.0\"',
    'set "WindowsSdkDir=C:\Program Files (x86)\Windows Kits\10\"',
    'set "RC=W:\bin\10.0.15063.0\x64\rc.exe"',
    'set "MT=W:\bin\10.0.15063.0\x64\mt.exe"',
    'set "PATH=W:\bin\10.0.15063.0\x64;%PATH%"',
    'set "INCLUDE=C:\Program Files (x86)\Windows Kits\10\include\10.0.15063.0\ucrt;C:\Program Files (x86)\Windows Kits\10\include\10.0.15063.0\shared;C:\Program Files (x86)\Windows Kits\10\include\10.0.15063.0\um;%INCLUDE%"',
    'set "LIB=C:\Program Files (x86)\Windows Kits\10\lib\10.0.15063.0\ucrt\arm;C:\Program Files (x86)\Windows Kits\10\lib\10.0.15063.0\um\arm;%LIB%"',
    "set `"LIB=%LIB%;$VCToolsLib`"",
    "set `"LIB=$($VCToolsRoot.FullName)\lib\arm\store;%LIB%`"",
    "`"$Root\vcpkg\vcpkg.exe`" install --triplet arm-uwp --overlay-triplets `"$Root\vcpkg-overlays\triplets`" --overlay-ports=`"$Root\vcpkg-overlays\ports`" --x-buildtrees-root=`"$BuildTreesRoot`" --binarysource=clear"
)
Set-Content -Path $VcpkgScript -Value $VcpkgLines -Encoding Ascii
$VcpkgCommand = "`"$VcpkgScript`""
Invoke-Checked $VcpkgCommand 'install vcpkg dependencies'

$CMake = (Get-ChildItem (Join-Path $Root 'vcpkg\downloads\tools') -Recurse -Filter cmake.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '4\.4\.0' } |
    Select-Object -First 1).FullName
if (-not $CMake) { Fail 'CMake 4.4 was not found under vcpkg\downloads\tools' }
$env:PATH = "$(Split-Path $CMake);$env:PATH"
Write-Log "CMake: $CMake"

Invoke-Checked "`"$Root\generate-thirdparty-projects-arm.bat`"" 'generate third-party projects'

$CommonCommand = (
    '"{0}" --build "{1}\third_party\moonlight-common-c\build" ' +
    '--config Release --target moonlight-common-c enet'
) -f $CMake, $Root
Invoke-Checked $CommonCommand 'build moonlight-common-c and enet'

$GamestreamCommand = (
    '"{0}" --build "{1}\libgamestream\build" --config Release --target gamestream'
) -f $CMake, $Root
Invoke-Checked $GamestreamCommand 'build gamestream'

$MSBuildScript = Join-Path $BuildTemp 'run-msbuild.cmd'
# Drop stale dependency DLLs staged by earlier builds: MSBuild copies by
# timestamp, so desktop-CRT leftovers from an older toolchain configuration
# would otherwise be repackaged unchanged.
$StageDir = Join-Path $Root 'ARM\Release\moonlight-xbox-dx'
if (Test-Path $StageDir) {
    Get-ChildItem $StageDir -Filter '*.dll' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $Root ('vcpkg_installed\arm-uwp\bin\' + $_.Name)) } |
        Remove-Item -Force
}
$MSBuildLines = @(
    '@echo off',
    "call `"$VsDevCmd`" -arch=arm -host_arch=x64 -winsdk=10.0.15063.0",
    'set "WindowsSDKVersion=10.0.15063.0\"',
    'set "WindowsSdkDir=C:\Program Files (x86)\Windows Kits\10\"',
    'set "WindowsSdkBinPath=W:\bin\10.0.15063.0\x64\"',
    'set "WindowsSdkVerBinPath=W:\bin\10.0.15063.0\x64\"',
    'set "RC=W:\bin\10.0.15063.0\x64\rc.exe"',
    'set "MT=W:\bin\10.0.15063.0\x64\mt.exe"',
    'set "PATH=W:\bin\10.0.15063.0\x64;%PATH%"',
    'set "INCLUDE=C:\Program Files (x86)\Windows Kits\10\include\10.0.15063.0\ucrt;C:\Program Files (x86)\Windows Kits\10\include\10.0.15063.0\shared;C:\Program Files (x86)\Windows Kits\10\include\10.0.15063.0\um;%INCLUDE%"',
    "set `"LIB=C:\Program Files (x86)\Windows Kits\10\lib\10.0.15063.0\ucrt\arm;C:\Program Files (x86)\Windows Kits\10\lib\10.0.15063.0\um\arm;%LIB%;$VCToolsLib`"",
    "set `"LIB=$($VCToolsRoot.FullName)\lib\arm\store;%LIB%`"",
    "`"$MSBuild`" third_party\DirectXTK\DirectXTK_Windows10_2022.vcxproj -t:Build -p:Configuration=Release -p:Platform=ARM -v:m -nologo",
    "`"$MSBuild`" moonlight-xbox-dx.vcxproj -t:Build -p:Configuration=Release -p:Platform=ARM -p:AppxPackage=true -p:GenerateAppxPackageOnBuild=true -p:AppxBundle=Never -p:AppxBundlePlatforms=ARM -p:UapAppxPackageBuildMode=SideloadOnly -p:AppxGeneratePrisForPortableLibrariesEnabled=false -p:UseDotNetNativeToolchain=false -p:PackageCertificateThumbprint=$CertificateThumbprint -v:m -nologo"
)
Set-Content -Path $MSBuildScript -Value $MSBuildLines -Encoding Ascii
$MSBuildCommand = "`"$MSBuildScript`""
Invoke-Checked $MSBuildCommand 'build and package Appx'

$Appx = Get-ChildItem (Join-Path $Root 'ARM\Release\AppPackages') -Recurse -Filter '*.appx' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $Appx) { Fail 'No .appx was produced' }

Write-Log ''
# Every packaged dependency DLL must import the UWP (app-container) CRT.
# A single DLL importing the desktop VCRUNTIME140.dll makes activation fail on
# the device with E_APPLICATION_ACTIVATION_EXEC_FAILURE (0x8027025B), and the
# process never starts, so there is no log and no dump to diagnose from.
$DumpBin = (Get-ChildItem (Join-Path $VsInstallPath 'VC\Tools\MSVC') -Recurse -Filter 'dumpbin.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -First 1).FullName
if (-not $DumpBin) { Fail 'dumpbin.exe not found in the Visual Studio installation' }
$GateDir = Join-Path $BuildTemp 'crt-gate'
if (Test-Path $GateDir) { Remove-Item $GateDir -Recurse -Force }
New-Item -ItemType Directory -Force $GateDir | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Zip = [System.IO.Compression.ZipFile]::OpenRead($Appx.FullName)
$Bad = @()
try {
    foreach ($Entry in $Zip.Entries) {
        if ($Entry.FullName -notmatch '^[^/]+\.dll$') { continue }
        if ($Entry.FullName -match '^(api-ms|vccorlib|VCRUNTIME|MSVCP|CONCRT|ucrtbase)') { continue }
        $Path = Join-Path $GateDir $Entry.FullName
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Path, $true)
        $Deps = & $DumpBin /nologo /dependents $Path 2>&1
        if ($Deps -match 'VCRUNTIME140\.dll') { $Bad += $Entry.FullName }
    }
}
finally {
    $Zip.Dispose()
}
if ($Bad.Count -gt 0) {
    Fail ('dependency DLLs link the desktop CRT instead of the UWP one: ' + ($Bad -join ', '))
}
Write-Log "CRT gate: all packaged dependency DLLs import VCRUNTIME140_APP.dll"
Write-Log 'BUILD OK'
Write-Log "APPX: $($Appx.FullName)"
Write-Log "SIZE: $($Appx.Length)"
Write-Log "LOG:  $Log"


