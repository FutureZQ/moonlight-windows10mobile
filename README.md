# moonlight-xbox for Windows 10 Mobile

A port of [Moonlight Stream](https://moonlight-stream.org/) for playing games using GeForce Experience or [Sunshine](https://github.com/LizardByte/sunshine), targeting Windows 10 Mobile phones (ARM32, build 15254). It is a fork of [TheElixZammuto/moonlight-xbox](https://github.com/TheElixZammuto/moonlight-xbox), which targets the Xbox One and Xbox Series X|S family of consoles.

**This application is still in early stages of development. Expect things to not work or working badly**

## Installation and Usage

### For Sideloading (you probably want to use this)

The Windows 10 Mobile Store publishing channel is closed, so the package has to be sideloaded.

1. Build or obtain `moonlight-xbox-dx_<version>_ARM.appx`
2. Make sure its signing certificate is trusted on the phone (Device Portal or the certificate manager)
3. Deploy the `.appx` through Device Portal or the enterprise package installer
4. Open Moonlight on the phone and, if not already, your host app
5. Press the "+" button, insert your PC IP address (IPv4 or IPv6, e.g. `192.168.1.10`, `192.168.1.10:47989` or `[2001:db8::10]:47989`) and press "Connect"
6. Pair if needed
7. Choose from the list below the application you want to run
8. Profit!

### For Dev Mode

1. Enable Developer Mode and Device Portal on the phone (Settings 閳?Update & security 閳?For developers)
2. Build the package with `.\build-w10m.ps1` (see [Building](#building)), or deploy the solution from Visual Studio 2022
3. Deploy `moonlight-xbox-dx_<version>_ARM.appx` through the Device Portal "Apps" page
4. Continue from step 4 of the sideloading instructions

The binary and project name stay `moonlight-xbox-dx` for compatibility with upstream.

## What does work

- Connection and Pairing (mDNS discovery, HTTPS, PIN pairing)
- Application list fetching, cover art, autostart selection
- Video streaming at 1280x720 with H.264 High Profile hardware decode (NV12 + D3D11 feature level 9_3 shaders)
- Host configuration on a per-host basis (resolution, FPS, bitrate, codec, frame pacing, audio buffer, packet size)
- Audio
- Gamepad input, including rumble and battery reporting
- Touch trackpad input and hardware mouse passthrough
- Graceful disconnection and back-button handling

## What does NOT work

- **Bluetooth peripherals while streaming on 2.4 GHz-only devices** (e.g. Lumia 640): the Bluetooth/Wi-Fi coexistence on that generation of hardware costs 20閳?0% of the Wi-Fi airtime, so the video stream stutters badly. Use the touchscreen, or turn Bluetooth off while streaming
- **60 FPS streams**: the composition swapchain on this platform needs two vblanks per displayed frame, so 30 FPS is the smooth ceiling. A 60 FPS stream renders at ~40 FPS and drops the rest
- HDR, and HEVC/H.265 on the phone: the codec is listed as upstream lists it, but the handshake advertises H.264 only, because feature level 9_3 exposes no hardware HEVC decoder - selecting HEVC on the phone still streams H.264
- PyroWave, and the ImGui performance graphs (disabled on Windows 10 Mobile)
- ARM64 and x64 packages: the port produces an ARM32 package only
- Everything else not listed above

## Building

### Requirements

- Windows 10 or Windows 11
- Visual Studio 2022 with:
    - C++ (v141) Universal Windows Platform tools for ARM
    - C++ (v143) build tools
    - Windows 10 SDK (10.0.15063.0) 閳?required for both the app and the ARM UWP dependencies
    - MSBuild
- PowerShell 5.1 or later
- Git with submodule support

### Steps to build

The one-shot script is the supported build path: it checks out the submodules, applies the patches, bootstraps vcpkg, installs the ARM UWP dependencies, builds DirectXTK and the C libraries, and produces the signed Appx.

1. Clone with submodules:

```powershell
git clone --recursive https://github.com/FutureZQ/moonlight-windows10mobile.git
cd moonlight-windows10mobile
```

2. Build (use `-Clean` for a from-scratch build):

```powershell
.\build-w10m.ps1 -Clean
```

3. The package is written to:

```text
ARM\Release\AppPackages\moonlight-xbox-dx_<version>_ARM_Test\
  moonlight-xbox-dx_<version>_ARM.appx
```

Run the script without `-Clean` for an incremental rebuild. The default signing thumbprint is a development certificate; pass your own with `-CertificateThumbprint <thumbprint>`.

The script handles the parts that a plain `msbuild` invocation would miss:

- applying the submodule patches stored in `patches/` (the gitlinks point at upstream commits)
- installing the vcpkg C dependencies with the `arm-uwp` overlay triplet and keeping the buildtrees outside the repository
- pinning `rc.exe` / `mt.exe`, `INCLUDE`, `LIB` and the SDK version to 10.0.15063 after `VsDevCmd`
- building `third_party\DirectXTK\DirectXTK_Windows10_2022.vcxproj` first, because the app includes the generated `Src\Shaders\Compiled\*.inc` blobs
- checking that every packaged dependency DLL imports the UWP CRT (`VCRUNTIME140_APP.dll`) before packaging

Toolchain split:

```text
main app / DirectXTK / tracy-xbox          v141 + SDK 15063
moonlight-common-c / enet / gamestream     v141 + SDK 15063
vcpkg C dependencies                       v143 + SDK 15063
```

The C11 dependencies (ffmpeg, openssl, curl, 閳? need v143; the app and the project's own C libraries stay on v141 so the 15063 XAML compiler does not have to run against newer MSBuild targets.

### CI and releases

The GitHub Actions workflow is `.github/workflows/w10m-release.yml`.

- Pushes to `master` and pull requests run the build
- A tag matching `v*` builds and signs the Appx, uploads the artifact, and publishes a GitHub Release
- `workflow_dispatch` can build a specific version

If the repository certificate secrets are not configured, CI creates a temporary self-signed certificate matching the manifest `Publisher` and uploads `cert.cer` next to the package.

## Credits

- [TheElixZammuto/moonlight-xbox](https://github.com/TheElixZammuto/moonlight-xbox)
- [moonlight-stream/moonlight-common-c](https://github.com/moonlight-stream/moonlight-common-c)
- [moonlight-stream](https://moonlight-stream.org/)
- [LizardByte/Sunshine](https://github.com/LizardByte/sunshine)
