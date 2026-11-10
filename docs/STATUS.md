# Windows 10 Mobile port status

Last updated: 2026-11-10

## Target

```text
Device OS        Windows 10 Mobile 15254
App model        UWP / WindowsStore
Target SDK       10.0.15063.0
Main toolset     v141 (14.16.27023)
Dependency C     v143 (14.44.35207), built by vcpkg
Triplet          arm-uwp (overlay)
```

## Verified builds

A clean local dependency install and full local build succeed:

```text
ARM\Release\AppPackages\moonlight-xbox-dx_1.18.3.0_ARM_Test\
  moonlight-xbox-dx_1.18.3.0_ARM.appx
```

```text
SIZE    11,775,698
SHA256  6D22FE4B9B88EE6E9B68E0B22069B8D46CC45F43FE67FEB6257DE4A6755B77D8
```

The same one-shot script succeeds in GitHub Actions:

```text
run      https://github.com/FutureZQ/moonlight-windows10mobile/actions/runs/42759854827
commit   59b747dbe7bad8794fc620335c55ce6c4df391e3
artifact moonlight-w10m-1.18.3
```

## Toolchain split

```text
main app / DirectXTK / tracy-xbox          v141 + SDK 15063
moonlight-common-c / enet / gamestream     v141 + SDK 15063
vcpkg C dependencies                       v143 + SDK 15063
```

`moonlight-common-c` and `gamestream` stay on v141 because the Visual Studio
UWP project for the C targets otherwise runs the 15063 XAML compiler and fails
with MSB4181. They are C code and do not need C11/P003 standards features.

The vcpkg dependencies (ffmpeg 8.1.2, openssl, curl, etc.) require C11 and are
therefore built with v143.

## vcpkg changes required by this port

### `patches/vcpkg.patch`

1. `scripts/detect_compiler/CMakeLists.txt`
   - accepts `WindowsStore` as well as `Windows` when deciding whether to skip
     the Ninja compiler probe.
2. `scripts/toolchains/uwp.cmake`
   - removes `/RTC1` from the debug flags. The v143 ARM toolset has no
     `runTmChk.lib`, so `/RTC1` leaves `_RTC_CheckStackVars` unresolved.

### Overlay port: `vcpkg-overlays/ports/vcpkg-cmake`

The ARM UWP ports are forced to use:

```text
-G "Visual Studio 17 2022"
-A "ARM,version=10.0.15063.0"
-T v143
```

The overlay also supplies the version bump needed to avoid reusing a cached
copy of the stock helper.

### Overlay triplet: `vcpkg-overlays/triplets/arm-uwp.cmake`

```text
target                 ARM32 UWP
SDK                    10.0.15063
msvc runtime           dynamic
CMAKE_SIZEOF_VOID_P    4
SDK tools              rc.exe / mt.exe from 15063
include                w10m-compat/sdkcompat first
linker                 crypt32, ws2_32, gdi32, user32, kernel32, advapi32
                       /NODEFAULTLIB:volatileaccessu.lib
warnings               /wd4703 (expat), /wd4146 (libpng)
```

## Build environment requirements

The one-shot script handles these automatically, but they are the reasons the
build is not just a plain `msbuild` invocation:

```text
vcpkg buildtrees        C:\Temp\w10m-vcpkg-buildtrees
SDK access              W: -> C:\Program Files (x86)\Windows Kits\10
MSVC libs               V: -> <VS>\VC\Tools\MSVC\<version>
VsDevCmd                -winsdk=10.0.15063.0
```

`W:` and `V:` give the linker space-free paths. The SDK environment must be
re-applied *after* `VsDevCmd` in a batch file; setting it in the parent
PowerShell process is not enough because `VsDevCmd` overwrites
`WindowsSDKVersion`, `LIB`, and `PATH`.

The Appx build first builds:

```text
third_party\DirectXTK\DirectXTK_Windows10_2022.vcxproj
```

That project generates the `Src\Shaders\Compiled\*.inc` blobs consumed by
`common\textconsole.cpp`. Without it, the app fails with:

```text
fatal error C1083: Cannot open include file:
  '../third_party/DirectXTK/Src/Shaders/Compiled/SpriteEffect_SpriteVertexShader.inc'
```

The XAML `MSB4181` that follows that missing include is secondary. Build
DirectXTK first and the XAML step completes.

## One-shot build

```powershell
.\build-w10m.ps1 -Clean
```

Use without `-Clean` for an incremental rebuild.

## SDK compatibility headers

`w10m-compat/sdkcompat` contains:

```text
OAIdl.h        from Windows SDK 19041 (fixes the 15063 /##/ C-mode error)
PropIdlBase.h  from Windows SDK 19041
stdalign.h     minimal _Alignas/_Alignof shim for v143
```

`gamingdeviceinformation.h` remains in `w10m-compat` for the v141 main app.

## Remaining work

- Confirm the published Release asset after the next tag build.
- Keep `ci_cloud`/`ci_debug` from drifting from the one-shot script.
- The local DSH shell has a low-integrity workspace ACL; `buildtrees` must stay
  outside it. This is a host limitation, not a project limitation.
