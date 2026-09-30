# Package

version       = "0.1.0"
author        = "crc32"
description   = "Windows system tray power plan switcher"
license       = "MIT"
srcDir        = "."

# Dependencies

# Note: wNim 1.0.0 crashes the Nim 2.2.x compiler VM on import
# (field 'floatVal' is not accessible ... kind = rkInt), so this project
# calls the Win32 API directly through winim instead.
requires "nim >= 2.0.0"
requires "winim >= 4.0.0"

task build_release, "Build release binary (no console window)":
  exec "nim c -d:release --app:gui --opt:size -o:bin/ppc ppc.nim"
