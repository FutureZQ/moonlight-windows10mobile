# Debug history - Windows 10 Mobile port

## 2026-11-09 - clean dependency build

The goal was a build with no prebuilt `vcpkg_installed` and no binary cache.

### Git version was a vcpkg-tool requirement

vcpkg-tool `2026-07-27` requires Git >= 2.55.0.windows.3. The machine had Git
2.50. vcpkg then tried to download PortableGit from GitHub and timed out.

Resolution: upgrade Git to 2.56.0.windows.4. This was unrelated to the app,
CMake, v141, v143, or the 15063 SDK.

### vcpkg compiler detection: WindowsStore + Ninja

`scripts/detect_compiler/CMakeLists.txt` only skipped the compiler test when:

```cmake
CMAKE_SYSTEM_NAME STREQUAL "Windows"
```

UWP reports `WindowsStore`. The test therefore compiled and linked a temporary
UWP executable. With the v143 ARM compiler this produced:

```text
cl: error D8050: unable to execute c1.dll
```

The historical `patches/vcpkg.patch` already carried this fix, but it had been
skipped when the dependency toolset was changed. Fixed to:

```cmake
CMAKE_SYSTEM_NAME MATCHES "Windows"
```

### MSBuildTemp was not writable

After switching to the Visual Studio generator, try_compile reached the Appx
signing step and failed:

```text
MSB6003
MSBuildTemp\tmp...exec.cmd
UnauthorizedAccessException
```

Setting `TMP`/`TEMP` to a writable directory under the repository fixed it.

### CMake tried to sign the compiler test app

Even with MSBuild working, try_compile built an EXE and the UWP packaging
targets tried to sign `Windows_TemporaryKey.pfx`:

```text
鏃犳硶鎵撳紑璇佷功: Windows_TemporaryKey.pfx
鎸囧畾鐨勭綉缁滃瘑鐮佷笉姝ｇ‘
```

Fixed by passing, before `project()`:

```cmake
-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
```

This is now appended by `vcpkg_configure_cmake.cmake` for WindowsStore.

### Ninja was still used for parallel configure

Disabling `ninja_can_be_used` alone was not enough; vcpkg has a separate
`ninja_host` used to run the release/debug configure jobs in parallel. Disabling
both and using the Visual Studio 17 2022 generator removed the remaining
`ninja.exe -v` path.

### OpenSSL UWP link imports

OpenSSL failed with unresolved:

```text
GetStdHandle
GetEnvironmentVariableW
VirtualLock
CertOpenSystemStoreW
```

Added the historical UWP linker imports to the overlay triplet:

```cmake
set(VCPKG_LINKER_FLAGS
  "crypt32.lib ws2_32.lib gdi32.lib user32.lib kernel32.lib advapi32.lib")
```

### FFmpeg and the 15063 COM headers

FFmpeg configure failed the d3d11va check because the 15063 `propidlbase.h`
does not compile under the v143 C front-end:

```text
propidlbase.h(319): error C2059: syntax error: '/'
```

The historical working archive showed FFmpeg had actually been built with
v143 + SDK 19041. For the 15063 dependency build, the fix was to put the fixed
SDK 19041 `OAIdl.h` and `PropIdlBase.h` in `w10m-compat/sdkcompat` and include
that directory before the SDK.

FFmpeg then needed `stdalign.h`; v143 does not ship one, so
`w10m-compat/sdkcompat/stdalign.h` provides `_Alignas`/`_Alignof` mappings.

### Result

The complete vcpkg dependency install succeeded, followed by
`moonlight-common-c`, `enet`, `gamestream`, the v141 app, and the ARM Appx.

```text
ARM\Release\AppPackages\moonlight-xbox-dx_1.18.3.0_ARM_Test\
  moonlight-xbox-dx_1.18.3.0_ARM.appx
```

## Notes for the next clean build

- Do not restore `vcpkg_installed` or `vcpkg\packages` from an archive when the
  purpose is to validate a clean build.
- Apply `patches/vcpkg.patch` before `vcpkg install`.
- Use `vcpkg-overlays/triplets/arm-uwp.cmake`, not the upstream triplet.
- Keep `TMP`/`TEMP` writable.
- `moonlight-common-c`/`enet`/`gamestream` remain v141 for now because the
  v143 UWP project triggers the 15063 XAML compiler (MSB4181); vcpkg C
  dependencies are v143.

## 2026-11-10 - low-integrity workspace, SDK pinning, and DirectXTK

Several failures on this date were environment failures, not compiler or ABI
failures.

### D8050 was a workspace ACL problem

The local DSH workspace is marked:

```text
Mandatory Label\Low Mandatory Level
Everyone:(DENY)(DeleteSubdirectoriesAndFiles)
```

`c1.dll` needs to write its debug record while compiling. Running the same
`cl.exe` command by hand worked, but Ninja/VS-built bzip2 failed with:

```text
error D8050: unable to execute c1.dll
```

The build succeeded when run elevated, and also when `vcpkg` buildtrees were
moved to a normal-integrity directory:

```text
C:\Temp\w10m-vcpkg-buildtrees
```

The script now always uses that external buildtrees root. This is why
`build-w10m.ps1` has `-BuildTreesRoot`.

### VsDevCmd overwrites the SDK selection

`-winsdk=10.0.15063.0` is not reliable when several SDKs are installed, and
environment variables set before `VsDevCmd` are overwritten by it. The vcpkg
and MSBuild steps therefore run from generated `.cmd` files that set
`WindowsSDKVersion`, `WindowsSdkDir`, `INCLUDE`, `LIB`, `PATH`, `RC`, and `MT`
*after* calling `VsDevCmd`.

`W:` and `V:` substitutions give the linker paths without spaces.

### vcpkg port generator

The ARM UWP ports were still selecting Ninja. An overlay `vcpkg-cmake` port
forces the Visual Studio 17 2022 generator and the ARM 15063 platform. This
avoids the c1/CRT issues on the CMake probe path and also avoids the
`LIBCMT.lib` and `volatileaccessu.lib` link failures.

### Expat and libpng warnings-as-errors

The overlay triplet suppresses two warnings that the dependency build turns
into errors under `/WX`:

```text
C4703  expat      potentially uninitialized local pointer
C4146  libpng     unary minus on unsigned type
```

These are upstream warnings, not ABI problems.

### The real Appx failure: DirectXTK shader blobs

CI reached the main app and then reported:

```text
fatal error C1083: Cannot open include file:
  '../third_party/DirectXTK/Src/Shaders/Compiled/SpriteEffect_SpriteVertexShader.inc'
```

followed by:

```text
MSB4181: CompileXaml returned false
```

The `Compiled` directory is generated by DirectXTK, not stored in the
submodule. Local builds had it from earlier runs; the clean CI workspace did
not.

Fix: build DirectXTK before the app:

```powershell
msbuild third_party\DirectXTK\DirectXTK_Windows10_2022.vcxproj `
  -t:Build -p:Configuration=Release -p:Platform=ARM
```

After that, both the missing include and the secondary XAML error disappear.

### Verified result

Local:

```text
SIZE    11,775,698
SHA256  6D22FE4B9B88EE6E9B68E0B22069B8D46CC45F43FE67FEB6257DE4A6755B77D8
```

GitHub Actions:

```text
run 42759854827
commit 59b747d
artifact moonlight-w10m-1.18.3
```


## 2026-11-11 - activation failure: desktop-CRT dependency DLLs

The app installed but never started: no splash, no `app.log`, no dump, and the
Device Portal reported `E_APPLICATION_ACTIVATION_EXEC_FAILURE` (0x8027025B) with
`TYPE_E_ELEMENTNOTFOUND` (0x8002802B) during the activation prerequisite phase.
ETW (`Microsoft-Windows-AppModel-Exec` / `Kernel-Process` / `User-Loader`)
showed that no image was ever loaded, so nothing in the app ran.

Root cause: the packaged dependency DLLs were built against the **desktop** CRT
(`VCRUNTIME140.dll`), while the UWP app imports `VCRUNTIME140_APP.dll`. Inside
the app container the desktop CRT is unavailable, so loading the statically
imported DLLs fails before any code runs.

Evidence:

```text
working dependency set (2026-11-07): 17/17 DLLs import VCRUNTIME140_APP.dll
broken  dependency set (2026-11-10): 17/17 DLLs import VCRUNTIME140.dll
app exe (both builds):              imports VCRUNTIME140_APP / vccorlib140_app
```

Working-tree fixes:

1. Restore the moonlight-xbox ffmpeg overlay port (`vcpkg-overlays/ports/ffmpeg`).
   It is the stock vcpkg port plus the upstream Xbox retry patch
   (`9900-check-d3derr-wasstilldrawing.patch`) and a W10M UWP configure branch
   that keeps only `--enable-d3d11va` (no mediafoundation/dxva2/d3d12va on 15063).
2. Build dependencies release-only (`set(VCPKG_BUILD_TYPE release)` in the
   overlay triplet); the debug UWP ARM link fails on `/RTC1`.
3. Verify the CRT flavor of every packaged DLL before shipping. A single DLL
   importing `VCRUNTIME140.dll` is enough to make activation fail.

Resolution (2026-11-11, verified from a clean tree): the UWP CRT import
libraries live in `VC\Tools\MSVC\<version>\lib\arm\store`; the desktop ones in
`lib\arm`. The linker searches `/LIBPATH` before `%LIB%`, and the overlay
triplet passed `/LIBPATH:V:/lib/arm` only, so every link resolved vcruntime.lib
to the desktop import library. Putting `/LIBPATH:V:/lib/arm/store` first (and
prepending the same directory to `%LIB%` in `build-w10m.ps1`) makes all
dependencies link `VCRUNTIME140_APP.dll` - a clean from-zero rebuild now yields
17/17 UWP dependency DLLs.

`build-w10m.ps1` now also removes stale staged dependency DLLs before MSBuild
(copies are timestamp-based) and fails the build if any packaged DLL imports the
desktop CRT.

## 2026-11-12 - Host settings crash: ComboBox.SelectedIndex before the page is live

Tapping a host and choosing its settings killed the app on the phone. `app.log`
shows the page constructor completing and then stops mid-population:

```text
[01:03:14.219] [HostSettings] ctor: begin (before InitializeComponent)
[01:03:14.245] [HostSettings] ctor: InitializeComponent ok
[01:03:14.257] [HostSettings] OnNavigatedTo: begin
[01:03:06.880] Hello from Moonlight!          <- next process start
```

The dump (`moonlight-xbox-dx.exe.4312.dmp`, 01:03) carries a WinRT stowed
exception with `ResultCode = 0x80070057` (`E_INVALIDARG`) and this stack:

```text
KERNELBASE!RaiseException
  <- __abi_WinRTraiseException
  <- HostSettingsPage::OnNavigatedTo+0x1103   [hostsettingspage.xaml.cpp:119]
  <- [IPageOverrides]::OnNavigatedTo
  <- Frame::Navigate
  <- HostSelectorPage::hostSettingsButton_Click
```

Line 119 was `FramePacingComboBox->SelectedIndex = i;`. `state.json` stores
`"framePacing":"Immediate"`, so the loop matched index 0 and executed the
assignment while the page was still in `OnNavigatedTo`. On 15254 a ComboBox whose
`ItemsSource` was assigned by `x:Bind` has not built its `Items` collection yet
at that point, so index 0 is out of range and the setter returns
`E_INVALIDARG`; C++/CX turns that into an unhandled exception and the process
dies.

The three saved selections (frame pacing, audio buffer, packet size) are now
applied in `OnLoaded` (`ApplySavedSelections`), each guarded against
`Items->Size`, and wrapped in a `Platform::Exception` handler that logs instead
of crashing. Log lines `framePacing/audioBuffer/packetSize: selected N of M`
confirm the realized item counts on the device.

Lesson: on 15254, never write `ComboBox.SelectedIndex` before `Loaded`; the
`ItemsSource`-bound `Items` view is still empty and any index is rejected.


## Device Portal access

All of the evidence above comes from the Device Portal REST API. The procedure
(cookie/CSRF handling, the token rotation trap, the `utf-8-sig` BOM trap, the
ETW WebSocket `Origin` header, and the multipart install request) is documented
in [DEVICE-PORTAL.md](DEVICE-PORTAL.md).
