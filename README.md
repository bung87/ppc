# PowerPlanSwitcher

A lightweight Windows system tray app written in [Nim](https://nim-lang.org/) for switching power plans.

## Features

- Sits in the system tray with a custom-drawn icon (blue circle + "P")
- Right-click or double-click the tray icon to open a popup menu listing all power plans, with the active one radio-checked
- Tooltip shows the current active power plan
- Balloon notification after switching plans
- Optional "Start at login" toggle (writes to the registry `Run` key)
- Re-creates the tray icon automatically when the taskbar restarts (e.g. after explorer.exe crashes)
- UI language follows the system language (English / 简体中文); power plan names come from Windows and are always localized

## How it works

- **Tray icon**: pure Win32 — `Shell_NotifyIconW` + `TrackPopupMenu` via [winim](https://github.com/khchen/winim); the icon is drawn at runtime with GDI into a 32-bit ARGB DIB (alpha channel set per-pixel), no `.ico` resource needed
- **Power plans**: Windows power management API (`powrprof.dll`) — `PowerEnumerate` / `PowerReadFriendlyName` / `PowerSetActiveScheme`; no `powercfg` subprocess and no console code-page issues with localized plan names
- **Auto-start**: registry key `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`

## Requirements

- Nim 2.x
- [winim](https://github.com/khchen/winim) 4.x (installed automatically by nimble)

## Build

```bash
nimble build            # release build, no console window, output: ./ppc.exe
```

or manually:

```bash
nim c -d:release --app:gui --opt:size -o:ppc.exe src/ppc.nim
```

## Package

```bash
nimble install -d       # install winim + nimpacker
nimble dist             # nimpacker build + zip -> dist/ppc-<version>-windows-x86_64.zip
```

`nimble dist` uses [nimpacker](https://github.com/nimpacker/nimpacker) to compile the
release binary (via `nimble build -d:release`; release flags `--app:gui --opt:size`
are set in [`config.nims`](config.nims)) into `build/windows/Release/`, then zips it
into `dist/`. App metadata for nimpacker (product name, Inno Setup appId, install
privileges) lives in [`nimpacker/meta.nims`](nimpacker/meta.nims); `nimpacker pack
--target windows` can additionally build an Inno Setup installer
(`dist/ppc-setup.exe`).

## Release

Pushing a tag starting with `v` (e.g. `git tag v0.1.0 && git push origin v0.1.0`)
triggers the [Release workflow](.github/workflows/release.yml), which runs
`nimble dist` on `windows-latest` and attaches the resulting zip to a GitHub
Release. Remember to bump `version` in `ppc.nimble` before tagging, since the
zip file name is derived from it.


## Usage

Run `ppc.exe` (from the zip, or `build/windows/Release/ppc.exe` after `nimble dist`). Right-click the tray icon:

- Select a power plan to activate it
- Check/uncheck **Start at login** to toggle auto-start
- Choose **Quit** (or the menu's exit item) to close the app

> Note: [wNim](https://github.com/khchen/wNim) was considered for the GUI, but its latest release (1.0.0) crashes the Nim 2.2 compiler VM on import (`field 'floatVal' is not accessible ... kind = rkInt`), so this project calls the Win32 API directly through winim instead.

## License

MIT
