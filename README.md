# moonlight-xbox for Windows 10 Mobile

A port of [Moonlight Stream](https://moonlight-stream.org/) for playing games using GeForce Experience or [Sunshine](https://github.com/LizardByte/sunshine), targeting Windows 10 Mobile phones (ARM32, build 15254). It is a fork of [TheElixZammuto/moonlight-xbox](https://github.com/TheElixZammuto/moonlight-xbox), which targets the Xbox One and Xbox Series X|S family of consoles.

Xbox-specific tuning notes inherited from upstream live in [FAQ.md](FAQ.md); most of them apply only partly to the phone.

## Installation and Usage

### For Sideloading (you probably want to use this)

The Windows 10 Mobile Store publishing channel is closed, so the package has to be sideloaded.

1. Obtain `moonlight-xbox-dx_<version>_ARM.appx` from the releases page or build it yourself
2. Make its signing certificate trusted on the phone (Device Portal or the certificate manager)
3. Deploy the `.appx` through Device Portal or the enterprise package installer
4. Open Moonlight, press "+", enter your PC address (IPv4 or IPv6, e.g. `192.168.1.10`, `192.168.1.10:47989` or `[2001:db8::10]:47989`) and press "Connect"
5. Pair if needed, then pick the application you want to run

### For Dev Mode

1. Enable Developer Mode and Device Portal on the phone (Settings > Update & security > For developers)
2. Build with `.\build-w10m.ps1` (see [Building](#building)), or deploy the solution from Visual Studio 2022
3. Deploy `moonlight-xbox-dx_<version>_ARM.appx` from the Device Portal "Apps" page
4. Continue from step 4 of the sideloading instructions

The binary and project name stay `moonlight-xbox-dx` for compatibility with upstream.

## What does work

- Connection, pairing, mDNS discovery and saved host history
- Application list with cover art and autostart selection
- H.264 High Profile hardware decode (NV12 + D3D11 feature level 9_3 shaders)
- Per-host settings: resolution, FPS (30/60/120), bitrate, codec, frame pacing, audio buffer, packet size
- Audio: stereo, 5.1 and 7.1
- Gamepad input with rumble and battery reporting, touch trackpad, hardware mouse passthrough
- On-screen keyboard, graceful disconnection and Back-button handling

## What does NOT work

- **HEVC (8-bit)** - not enabled (untested); its NV12 decode and render path is the one H.264 already uses.
- **HDR** - not implemented; in this protocol it only exists as 10-bit, and the phone renders 8-bit NV12.
- **PyroWave** - platform limit; its decoder needs D3D12, which Windows 10 Mobile does not have.
- **Stats graphs** - not enabled (untested); ImGui crashes on ARM32, so the overlay is skipped. Text stats work.
- **Bluetooth while streaming on 2.4 GHz-only devices** - hardware limit; use the touchscreen or turn Bluetooth off.
- **ARM64 and x64 packages** - ARM32 only.
- Everything else not listed above.

## Building

### Requirements

- Windows 10 or 11
- Visual Studio 2022 with C++ (v141) UWP ARM tools, C++ (v143) build tools, Windows 10 SDK 10.0.15063.0 and MSBuild
- PowerShell 5.1 or later, Git with submodule support

### Steps to build

Clone with submodules and run the one-shot script:

```powershell
git clone --recursive https://github.com/FutureZQ/moonlight-windows10mobile.git
cd moonlight-windows10mobile
.\build-w10m.ps1 -Clean
```

The package is written to `ARM\Release\AppPackages\moonlight-xbox-dx_<version>_ARM_Test\`. Drop `-Clean` for an incremental rebuild, and pass `-CertificateThumbprint <thumbprint>` to sign with your own certificate.

The script is the supported path: it applies the submodule patches from `patches/`, installs the vcpkg ARM UWP dependencies with the overlay triplet, pins the toolchain to SDK 15063, builds DirectXTK first because the app includes its compiled shader blobs, and checks that every packaged DLL imports `VCRUNTIME140_APP.dll`.

Toolchain split:

```text
app / DirectXTK / tracy-xbox / project C libraries   v141 + SDK 15063
vcpkg C dependencies (ffmpeg, openssl, curl)         v143 + SDK 15063
```

### CI

`.github/workflows/w10m-release.yml` builds on pushes and pull requests to `master`; any `v*` tag signs the Appx, uploads it and publishes a GitHub Release, and `workflow_dispatch` builds a specific version. Without repository certificate secrets, CI generates a temporary self-signed certificate matching the manifest `Publisher` and ships `cert.cer` next to the package.

## Credits

- [TheElixZammuto/moonlight-xbox](https://github.com/TheElixZammuto/moonlight-xbox) - upstream
- [moonlight-stream/moonlight-common-c](https://github.com/moonlight-stream/moonlight-common-c)
- [moonlight-stream](https://moonlight-stream.org/) and [LizardByte/Sunshine](https://github.com/LizardByte/sunshine)
