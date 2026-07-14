# Xn Fresh Deploy

Native Windows app for FiveM server profiles, safe soundpack/ReShade switching, startup commands, and guided PC setup.

**No PowerShell. No separate .NET install.** Extract the release ZIP and run `XnFreshDeploy.exe`.

## Download

**[Download XnFreshDeploy v4.1 (ZIP)](https://github.com/WHOMEANSWHO/xn-fresh-deploy/releases/download/v4.1/XnFreshDeploy-v4.1.zip)** — ~58 MB, Windows 10/11 64-bit

Or browse all releases: https://github.com/WHOMEANSWHO/xn-fresh-deploy/releases

Verify the EXE hash against `SHA256SUMS.txt` inside the ZIP:

```
5B417D9C12102FF1CAD40E9CE6159C105E6A4F2B15880F68874889580532FE0A  XnFreshDeploy.exe
```

## Quick start

1. Extract the ZIP to a writable folder (Desktop, Documents, USB).
2. Run `XnFreshDeploy.exe`.
3. Add a server profile, import packs in **Library**, hit **Play**.

See `START HERE.txt` and `README.md` in the release folder for full details.

## Build from source

Requires [.NET 8 SDK](https://dotnet.microsoft.com/download).

```powershell
.\Build-NativeRelease.ps1 -Version 4.1
```

Output: `XnFreshDeploy-v4.1.zip`

Optional code signing: see [docs/CODE_SIGNING.md](docs/CODE_SIGNING.md).

## Features

- Server profiles with connect codes, soundpacks, ReShade looks, and commands
- Safe pack switching with rollback
- Pack library with drag-and-drop import
- PC setup via winget, drivers, FiveM, ReShade
- Portable backups and legacy import from PowerShell versions
- Auto-update check, crash logs, first-run guide

## Requirements

- Windows 10/11 64-bit
- FiveM opened once before applying packs

## License

Community tool — use at your own risk. Not affiliated with FiveM or Cfx.re.
