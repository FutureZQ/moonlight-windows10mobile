# Moonlight for Windows 10 Mobile

A Windows 10 Mobile (ARM32) port of [moonlight-xbox](https://github.com/TheElixZammuto/moonlight-xbox), itself a port of [Moonlight Stream](https://moonlight-stream.org/) for playing games from GeForce Experience or [Sunshine](https://github.com/LizardByte/sunshine).

This repository is the Windows 10 Mobile port, maintained at [FutureZQ/moonlight-windows10mobile](https://github.com/FutureZQ/moonlight-windows10mobile). The upstream Xbox project and its history are credited in the release branch.

**Status: experimental, but buildable and runnable.** The target device is a Lumia-class Windows 10 Mobile phone (ARM32, build 15254) with D3D11 feature level 9_3 and H.264 High Profile hardware decode. PC/Xbox targets are not the focus of this fork.

## What works

- mDNS host discovery, HTTPS, PIN pairing
- Host list, app list, cover art
- ARM32 H.264 decode at 1280x720, NV12 + 9_3 shader rendering
- Audio, touch/trackpad input, Bluetooth mouse passthrough
- Graceful disconnect and back-button handling

## Install (sideload)

The Windows 10 Mobile Store publishing channel is closed. Install the signed `.appx` through Device Portal or enterprise sideloading:

1. Build or obtain `moonlight-xbox-dx_<version>_ARM.appx`.
2. Make sure the signing certificate is trusted on the phone.
3. Deploy through Device Portal or the package installer.
4. Start Moonlight, add the host, and pair with the PIN shown by Sunshine.

The binary/project name remains `moonlight-xbox-dx` for compatibility with the upstream codebase.

## Building

### Requirements

- Windows 10 or Windows 11
- Visual Studio 2022 with:
  - C++ (v141) Universal Windows Platform tools
  - C++ (v143) build tools
  - Windows 10 SDK 10.0.15063.0
  - MSBuild
- PowerShell 5.1 or later
- Git with submodule support

### One-shot build

This is the supported build path. It prepares submodules, bootstraps vcpkg, installs the ARM UWP dependencies, builds DirectXTK, the C libraries, and the Appx:

```powershell
git clone --recursive https://github.com/FutureZQ/moonlight-windows10mobile.git
cd moonlight-windows10mobile
.\build-w10m.ps1 -Clean
```

Output:

```text
ARM\Release\AppPackages\moonlight-xbox-dx_<version>_ARM_Test\
  moonlight-xbox-dx_<version>_ARM.appx
```

Use the script without `-Clean` for an incremental rebuild.

The script does the following automatically:

- applies the submodule patches in `patches/`
- installs vcpkg C dependencies with the `arm-uwp` overlay triplet
- keeps vcpkg buildtrees at `C:\Temp\w10m-vcpkg-buildtrees`
- pins `rc.exe` / `mt.exe` and the vcpkg/MSBuild environment to SDK 15063
- uses the overlay `vcpkg-cmake` port to build ARM UWP dependencies with the
  Visual Studio generator
- builds `third_party\DirectXTK\DirectXTK_Windows10_2022.vcxproj` so the
  shader `Compiled\*.inc` files exist before the app compiles
- signs the Appx with the supplied certificate thumbprint

The default certificate thumbprint is a development certificate. Pass your own:

```powershell
.\build-w10m.ps1 -Clean -CertificateThumbprint <thumbprint>
```

### Toolchain split

```text
main app / DirectXTK / tracy-xbox          v141 + SDK 15063
moonlight-common-c / enet / gamestream     v141 + SDK 15063
vcpkg C dependencies                       v143 + SDK 15063
```

The C11 dependencies (ffmpeg, openssl, curl, etc.) are compiled with v143.
The app and the project's C libraries stay on v141 so the 15063 XAML compiler
does not have to run against newer MSBuild targets.

### CI and releases

The GitHub Actions workflow is `.github/workflows/w10m-release.yml`.

- Pushes to `master` and pull requests run the build.
- A tag matching `v*` builds the Appx, signs it, uploads the artifact, and
  publishes a GitHub Release.
- `workflow_dispatch` can build a specific version.

The latest verified CI run is:

```text
run      42759854827
commit   59b747d
artifact moonlight-w10m-1.18.3
```

If repository certificate secrets are not configured, CI creates a temporary
self-signed certificate matching the manifest `Publisher` and uploads
`cert.cer` with the package.

### Debugging build failures

See [docs/DEBUG-HISTORY.md](docs/DEBUG-HISTORY.md) for the host-specific
problems that have already been diagnosed, including:

- the low-integrity/ACL c1.dll D8050 failure
- why vcpkg buildtrees must not live in a restricted workspace
- SDK 15063 selection after `VsDevCmd`
- the DirectXTK shader files that must be generated before the Appx build

Build logs are written to `build-logs/`; CI uploads them as
`one-shot-build-logs` on failure.

## Known limitations

- ARM32 only; no ARM64 or x64 package is produced.
- The Appx uses a self-signed/test certificate unless release secrets are set.
- Windows 10 Mobile Store publishing is no longer available.
- The port targets SDK 15063 and Windows 10 Mobile 15254; newer SDKs are not a
  supported target for the Appx.

## Credits

- [TheElixZammuto/moonlight-xbox](https://github.com/TheElixZammuto/moonlight-xbox)
- [moonlight-stream/moonlight-common-c](https://github.com/moonlight-stream/moonlight-common-c)
- [moonlight-stream](https://moonlight-stream.org/)
- [LizardByte/Sunshine](https://github.com/LizardByte/sunshine)
