# Package

version       = "0.2.0"
author        = "crc32"
description   = "Windows system tray power plan switcher"
license       = "MIT"
srcDir        = "src"
bin           = @["ppc"]

# Dependencies

# Note: wNim 1.0.0 crashes the Nim 2.2.x compiler VM on import
# (field 'floatVal' is not accessible ... kind = rkInt), so this project
# calls the Win32 API directly through winim instead.
requires "nim >= 2.0.0"
requires "winim >= 4.0.0"

# Packaging tool used by the `dist` task (installed via `nimble install -d` or
# from git: nimble install https://github.com/bung87/nimpacker). Scoped to the
# task because it is not in nimble's official package list.
taskRequires "dist", "nimpacker >= 0.2.6"

# Release flags (--app:gui --opt:size) are set in config.nims, so both
# `nimble build -d:release` (used by nimpacker) and manual `nim c -d:release`
# produce a GUI-subsystem, size-optimized binary.

task dist, "Package release binary with nimpacker into dist/":
  # nimpacker only ships a .cmd shim (no .exe), so route through cmd /c;
  # use the explicit .cmd name — a bare "nimpacker" would hit the extensionless
  # bash shim that nimble also installs. nimpacker compiles via `nimble build`
  # (see above) and moves the exe to build/windows/Release/ppc.exe
  exec "cmd /c nimpacker.cmd build --target windows --release"
  mkDir "dist"
  let zipName = "dist/ppc-" & version & "-windows-x86_64.zip"
  rmFile zipName
  exec "powershell -NoProfile -Command Compress-Archive -Path build/windows/Release/ppc.exe -DestinationPath " & zipName
