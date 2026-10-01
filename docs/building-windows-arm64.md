# Building Dusklight for Windows 11 ARM64 (command line)

This guide builds a native ARM64 Dusklight from a terminal on a Windows 11 ARM64 machine,
using the MSVC toolchain and the `windows-arm64-msvc` CMake preset. For general build
information see [building.md](building.md).

## Prerequisites

* **Visual Studio 2026** (Community or higher) with the `Desktop development with C++` workload, including:
  * `MSVC Build Tools for ARM64/ARM64EC` (ARM64-hosted compiler)
  * `Windows 11 SDK`
  * `C++ CMake tools for Windows` (provides CMake 3.25+ and Ninja)
* **Python 3** (the native ARM64 build from [python.org](https://www.python.org/downloads/windows/) is fine), available on `PATH`.
* **Rust** via [rustup](https://rustup.rs) with the ARM64 MSVC target:

  ```powershell
  rustup target add aarch64-pc-windows-msvc
  ```

* **Git**.

No vcpkg packages are required for a local build; the remaining dependencies come from
git submodules or are downloaded by CMake during configuration.

## 1. Get the source

```powershell
git clone --recursive https://github.com/TwilitRealm/dusklight.git
cd dusklight
git submodule update --init --recursive
```

## 2. Open an ARM64 developer shell

The `windows-arm64-msvc` preset expects the MSVC environment to be set up beforehand
(`"strategy": "external"`). In PowerShell, load the Visual Studio developer environment
for an ARM64 host and target (adjust the path to your Visual Studio edition):

```powershell
& "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\Launch-VsDevShell.ps1" `
    -Arch arm64 -HostArch arm64 -SkipAutomaticLocation
```

Alternatively, open **Developer PowerShell for VS** / **ARM64 Native Tools Command Prompt**
from the Start menu.

Check that the ARM64 compiler is active:

```powershell
(Get-Command cl).Source   # should end in ...\bin\Hostarm64\arm64\cl.exe
```

## 3. Configure

The `windows-arm64-msvc` preset does not set a build type, so pass one explicitly:

```powershell
cmake --preset windows-arm64-msvc `
    -DCMAKE_BUILD_TYPE=RelWithDebInfo `
    -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL
```

For a debug build use `-DCMAKE_BUILD_TYPE=Debug -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDebugDLL`.

The first configure downloads several dependencies and can take a few minutes.

## 4. Build

There is no build preset for this configuration, so build the directory directly:

```powershell
cmake --build build/windows-arm64-msvc
```

## 5. Run

```powershell
build\windows-arm64-msvc\dusklight.exe --dvd C:\path\to\game.iso
```

Supported disc formats: ISO (GCM), RVZ, WIA, WBFS, CISO, GCZ.

To produce a self-contained folder (executable, DLLs, `res/`, `mods/`) in `build/install`:

```powershell
cmake --install build/windows-arm64-msvc
```

## Troubleshooting

* **`'vswhere.exe' is not recognized`** printed when launching the dev shell: harmless, the
  environment is still set up correctly.
* **Wrong architecture / `x64` compiler picked up**: you are in an x64 developer shell. Open a
  new terminal and rerun step 2 with `-Arch arm64 -HostArch arm64`, then delete
  `build/windows-arm64-msvc` and configure again.
* **Rust target errors** (`can't find crate for core`, missing `aarch64-pc-windows-msvc`): run
  `rustup target add aarch64-pc-windows-msvc`.
* **Cross-compiling from an x64 machine**: use `-Arch arm64 -HostArch amd64` in step 2. The
  resulting binaries won't run on the x64 host.
