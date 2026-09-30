# PowerPlanSwitcher

A lightweight Windows system tray app written in [Nim](https://nim-lang.org/) for switching power plans.

## Features

- Sits in the system tray with a custom-drawn icon (blue circle + "P")
- Right-click or double-click the tray icon to open a popup menu listing all power plans, with the active one radio-checked
- Tooltip shows the current active power plan
- Balloon notification after switching plans
- Optional "Start at login" toggle (writes to the registry `Run` key)
- Re-creates the tray icon automatically when the taskbar restarts (e.g. after explorer.exe crashes)

## How it works

- **Tray icon**: pure Win32 — `Shell_NotifyIconW` + `TrackPopupMenu` via [winim](https://github.com/khchen/winim); the icon is drawn at runtime with GDI into a 32-bit ARGB DIB (alpha channel set per-pixel), no `.ico` resource needed
- **Power plans**: Windows power management API (`powrprof.dll`) — `PowerEnumerate` / `PowerReadFriendlyName` / `PowerSetActiveScheme`; no `powercfg` subprocess and no console code-page issues with localized plan names
- **Auto-start**: registry key `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`

## Requirements

- Nim 2.x
- [winim](https://github.com/khchen/winim) 4.x (installed automatically by nimble)

## Build

```bash
nimble build_release    # release build, no console window, output: bin/ppc.exe
```

or manually:

```bash
nim c -d:release --app:gui --opt:size -o:bin/ppc ppc.nim
```

## Usage

Run `bin/ppc.exe`. Right-click the tray icon:

- Select a power plan to activate it
- Check/uncheck **Start at login** to toggle auto-start
- Choose **Quit** (or the menu's exit item) to close the app

> Note: [wNim](https://github.com/khchen/wNim) was considered for the GUI, but its latest release (1.0.0) crashes the Nim 2.2 compiler VM on import (`field 'floatVal' is not accessible ... kind = rkInt`), so this project calls the Win32 API directly through winim instead.

## License

MIT
