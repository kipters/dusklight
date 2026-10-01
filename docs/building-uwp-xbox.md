# Building Dusklight for Xbox (UWP)

Dusklight can be built as a UWP app package that runs on an Xbox One or Xbox Series X|S in
[Developer Mode](https://learn.microsoft.com/windows/uwp/xbox-apps/devkit-activation), and on Windows.
For general build information see [building.md](building.md).

## How it works

SDL3, which Dusklight and aurora use for windowing, input and audio, has no UWP support. For UWP
builds (`DUSK_UWP=ON`, which sets aurora's `AURORA_UWP`):

* aurora's UWP host (`extern/aurora/lib/uwp`) owns the `CoreWindow` and runs the game's `main` on
  the UI thread.
* SDL is built from source as a static library without its Win32 video and joystick drivers
  (`extern/aurora/cmake/patches/apply-sdl3-uwp-host.cmake`). SDL's offscreen video driver
  provides a proxy `SDL_Window` that the host keeps the same size as the `CoreWindow`.
* Dawn renders to the `CoreWindow` directly. On Xbox, aurora uses D3D11 by default: Dawn's D3D12
  device is removed by the console's driver (`DXGI_ERROR_DRIVER_INTERNAL_ERROR`) as soon as it
  creates its first render pipeline. A D3D12 backend selected explicitly in the settings is
  still honored.
* Xbox controllers are read through `Windows.Gaming.Input` and exposed to SDL as virtual
  gamepads, so the game sees normal SDL gamepads, rumble included.
* Audio is rendered through WASAPI (`ActivateAudioInterfaceAsync`) from the SDL audio stream the
  game already produces (see `aurora/audio.h`).
* User data (config, saves, logs, caches) lives in the app's `LocalState` folder, under
  `TwilitRealm\Dusklight`.

These features aren't available in the UWP build:

* Code mods: UWP apps on Xbox can't load native mod DLLs or patch code at runtime.
* Discord Rich Presence, Sentry crash reporting.
* Picking a disc image through a file dialog. The disc image is passed on the command line
  instead; see [Providing the disc image](#providing-the-disc-image).
* Mouse and touch input. A keyboard works for menu navigation and text entry.
* Restarting from within the app (settings that need a restart apply on the next launch).

## Prerequisites

* Everything from the Windows section of [building.md](building.md): Visual Studio 2026 with
  `Desktop development with C++`, `Windows 11 SDK` and `C++ CMake tools for Windows`, plus Python 3.
* `MSVC Build Tools for x64/x86`. Xbox needs an x64 build; on an ARM64 PC this component
  includes the ARM64-hosted x64 cross compiler.

The Visual Studio UWP workload isn't required: the build uses the C++/WinRT headers from the
Windows SDK, and deploys the C++ runtime inside the package.

## Build

Open a Visual Studio developer shell targeting x64. From an ARM64 PC, cross-compile with
`-HostArch arm64`:

```powershell
& "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\Launch-VsDevShell.ps1" `
    -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
```

Configure and build:

```powershell
cmake --preset uwp-x64
cmake --build --preset uwp-x64
```

This produces a loose package layout in `build\uwp-x64\uwp\layout` (`AppxManifest.xml`,
`dusklight.exe`, its DLLs, `res\`). The layout can be registered directly; packing isn't needed
during development.

To produce a signed `.msix` instead:

```powershell
cmake --build --preset uwp-x64-package
```

The package lands in `build\uwp-x64\uwp\Dusklight_<version>_x64.msix`. By default it's signed with
a self-signed development certificate generated on first use (`build\uwp-x64\uwp\dusklight-dev.pfx`
and `.cer`). To use your own, set `DUSK_UWP_CERTIFICATE` (and `DUSK_UWP_CERTIFICATE_PASSWORD`),
and set `DUSK_UWP_PUBLISHER` to the certificate's subject.

`dusklight_uwp_package` first runs `dusklight_uwp_check`, which fails if any binary in the layout
imports a Windows API that isn't available on every device family that runs UWP apps, Xbox
included. Imports that load but may be denied inside the app container are listed as warnings.
You can run the check on its own:

```powershell
cmake --build build\uwp-x64 --target dusklight_uwp_check
```

## Providing the disc image

Dusklight needs a disc image of the game. You can embed it in the package, or upload it to the
app's data folder.

### Embedding the image in the package

Set `DUSK_UWP_EMBED_ISO` to the image when configuring:

```powershell
cmake --preset uwp-x64 -DDUSK_UWP_EMBED_ISO="P:\path\to\game.iso"
```

The image is added to the layout as `disc\game.iso`, as a hard link when the build directory is on
the same drive, so it isn't copied. The app is launched with `--dvd` pointing at it.

> [!WARNING]
> A package with an embedded image contains the game. Keep it to your own devices and never
> share it.

### Uploading the image to the app's data folder

Without `DUSK_UWP_EMBED_ISO`, the app looks for the image at `LocalState\game.iso` in its data
folder. On Xbox, upload it with the Device Portal's **File explorer**:
`LocalAppData\TwilitRealm.Dusklight_<id>\LocalState`. On Windows, the folder is
`%LOCALAPPDATA%\Packages\TwilitRealm.Dusklight_<id>\LocalState`.

The arguments are read from `aurora-args.txt` in the package root, one per line, followed by
those in `LocalState\aurora-args.txt` if it exists. Upload the latter with the Device Portal to
pass other options, such as `--develop` or `--log-level debug`, without rebuilding the package.
`{InstalledLocation}` and `{LocalFolder}` are replaced with the package directory and the
`LocalState` folder.

## Deploy to Xbox

1. Put the console in [Developer Mode](https://learn.microsoft.com/windows/uwp/xbox-apps/devkit-activation)
   and open the Device Portal (`https://<console-ip>:11443`) from your PC.
2. Under **Home**, choose **Add** and select `Dusklight_<version>_x64.msix`. To deploy the loose
   layout instead, use **Register** with `build\uwp-x64\uwp\layout` on a network share the
   console can reach.
3. In Dev Home, select Dusklight, press the View button, and in **View details** set the app type to
   **Game**. Apps get a much smaller share of memory and GPU than games.
4. Launch Dusklight from Dev Home.

Logs are written to `LocalState\TwilitRealm\Dusklight\logs`, and can be downloaded with the Device
Portal's file explorer.

Updating an installed package requires a higher package version. While iterating, build without
`DUSK_UWP_EMBED_ISO` (the package is then about 35 MB), upload the disc image to `LocalState` once,
and bump `DUSK_UWP_VERSION_OVERRIDE` for each deployment; updates keep `LocalState`:

```powershell
cmake --preset uwp-x64 -DDUSK_UWP_EMBED_ISO= -DDUSK_UWP_VERSION_OVERRIDE=2.0.3.1
cmake --build --preset uwp-x64-package
```

## Run on Windows

Enable Developer Mode in Windows Settings, then register the layout:

```powershell
Add-AppxPackage -Register build\uwp-x64\uwp\layout\AppxManifest.xml
```

and start Dusklight from the Start menu. Remove it with
`Get-AppxPackage TwilitRealm.Dusklight | Remove-AppxPackage`.

To install the `.msix` instead, first trust the development certificate:
`Import-Certificate -FilePath build\uwp-x64\uwp\dusklight-dev.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople`
from an elevated shell.
