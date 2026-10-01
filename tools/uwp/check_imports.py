#!/usr/bin/env python3
"""Report imports in a UWP package layout that may not resolve on Xbox.

Every DLL import of every PE file in the layout is compared against two
umbrella import libraries from the Windows SDK:

* OneCoreUAP.lib covers the APIs present on every Windows 10+ device family
  that runs UWP apps, Xbox included. Imports outside it are errors: the
  module will most likely fail to load on Xbox.
* WindowsApp.lib covers the APIs UWP apps are allowed to call. Imports
  outside it (but inside OneCoreUAP) are warnings: they load fine, but the
  call may be denied by the app container at runtime.

Delay-loaded imports are only resolved when first called, so they are
reported as warnings regardless.

Imports satisfied by a DLL shipped inside the layout, the CRT, or a small
allowlist of OS DLLs are always accepted.
"""

import argparse
import collections
import os
import re
import subprocess
import sys
from pathlib import Path

# OS DLLs present on every device family that the umbrella libraries don't cover.
# Rust's std links to these directly.
ALLOWED_DLLS = {
    "ntdll.dll",
    "bcryptprimitives.dll",
}
ALLOWED_DLL_PREFIXES = (
    "api-ms-win-crt-",
    "vcruntime140",
    "msvcp140",
    "concrt140",
    "ucrtbase",
)


def run_dumpbin(dumpbin: str, *args: str) -> str:
    result = subprocess.run([dumpbin, "/nologo", *args], capture_output=True, text=True,
                            encoding="mbcs" if os.name == "nt" else "utf-8", errors="replace")
    if result.returncode != 0:
        sys.exit(f"dumpbin {' '.join(args)} failed:\n{result.stdout}{result.stderr}")
    return result.stdout


class ImportLibrary:
    def __init__(self, dumpbin: str, path: Path):
        self.symbols: set[str] = set()
        self.dlls: set[str] = set()
        for line in run_dumpbin(dumpbin, "/headers", str(path)).splitlines():
            if match := re.match(r"\s+Symbol name\s+:\s+(\S+)", line):
                self.symbols.add(match.group(1))
            elif match := re.match(r"\s+DLL name\s+:\s+(\S+)", line):
                self.dlls.add(match.group(1).lower())

    def provides(self, dll: str, symbol: str) -> bool:
        # Ordinal imports can't be matched by name; accept them from DLLs the library references.
        if symbol.startswith("Ordinal"):
            return dll in self.dlls
        return symbol in self.symbols


def parse_imports(text: str) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    """Returns (regular imports, delay-loaded imports), each keyed by lowercase DLL name."""
    imports: dict[str, list[str]] = collections.defaultdict(list)
    delay_imports: dict[str, list[str]] = collections.defaultdict(list)
    target = imports
    current = None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == "Summary":
            break
        if stripped.startswith("Section contains the following delay load imports"):
            target = delay_imports
            current = None
            continue
        if stripped.startswith("Section contains the following imports"):
            target = imports
            current = None
            continue
        if dll := re.match(r"^    (\S+\.(?:dll|drv|exe))$", line, re.IGNORECASE):
            current = dll.group(1).lower()
            continue
        if current is None:
            continue
        if sym := re.match(r"^\s+(?:[0-9A-Fa-f]+\s+)+(\S+)$", line):
            name = sym.group(1)
            if not re.fullmatch(r"[0-9A-Fa-f]+", name):
                target[current].append(name)
        elif ordinal := re.match(r"^\s+(?:[0-9A-Fa-f]+\s+)*Ordinal\s+(\d+)$", line):
            target[current].append(f"Ordinal {ordinal.group(1)}")
    return imports, delay_imports


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dumpbin", default="dumpbin")
    parser.add_argument("--sdk-lib-dir", required=True,
                        help="Windows SDK um library directory for the target architecture (contains WindowsApp.lib)")
    parser.add_argument("--allow", action="append", default=[], help="Extra DLL name to accept (repeatable)")
    parser.add_argument("--strict", action="store_true", help="Exit with status 1 if any errors are found")
    parser.add_argument("layout", help="Package layout directory, or a single PE file")
    args = parser.parse_args()

    sdk_lib_dir = Path(args.sdk_lib_dir)
    windows_app = ImportLibrary(args.dumpbin, sdk_lib_dir / "WindowsApp.lib")
    one_core_uap = ImportLibrary(args.dumpbin, sdk_lib_dir / "OneCoreUAP.lib")

    layout = Path(args.layout)
    files = [layout] if layout.is_file() else sorted(
        p for p in layout.rglob("*") if p.suffix.lower() in (".exe", ".dll"))
    local_dlls = {p.name.lower() for p in files}
    allowed_dlls = ALLOWED_DLLS | {d.lower() for d in args.allow}

    def accepted(dll: str) -> bool:
        return dll in local_dlls or dll in allowed_dlls or dll.startswith(ALLOWED_DLL_PREFIXES)

    errors = 0
    warnings = 0
    for path in files:
        imports, delay_imports = parse_imports(run_dumpbin(args.dumpbin, "/imports", str(path)))
        lines = []
        for dll, symbols in sorted(imports.items()):
            if accepted(dll):
                continue
            missing = sorted(s for s in symbols if not one_core_uap.provides(dll, s))
            restricted = sorted(s for s in symbols
                                if one_core_uap.provides(dll, s) and not windows_app.provides(dll, s))
            if missing:
                lines.append(f"  error: {dll}: {', '.join(missing)}")
                errors += len(missing)
            if restricted:
                lines.append(f"  warning: {dll} (not in WindowsApp.lib): {', '.join(restricted)}")
                warnings += len(restricted)
        for dll, symbols in sorted(delay_imports.items()):
            if accepted(dll):
                continue
            unsafe = sorted(s for s in symbols if not windows_app.provides(dll, s))
            if unsafe:
                lines.append(f"  warning: {dll} (delay-loaded, must not be called): {', '.join(unsafe)}")
                warnings += len(unsafe)
        if lines:
            print(path.relative_to(layout) if layout.is_dir() else path)
            print("\n".join(lines))

    print(f"\n{errors} error(s), {warnings} warning(s)")
    return 1 if errors and args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
