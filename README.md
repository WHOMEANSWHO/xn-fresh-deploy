# Xn Fresh Deploy

Native Windows app for FiveM server profiles, safe soundpack/ReShade switching, startup commands, and guided PC setup.

**No PowerShell. No separate .NET install.** Extract the release ZIP and run `XnFreshDeploy.exe`.

## Download

Get the latest release from [GitHub Releases](https://github.com/WHOMEANSWHO/xn-fresh-deploy/releases).

Verify the EXE hash against `SHA256SUMS.txt` inside the ZIP.

```
42F0407E88982840724E3ED409D2E92B5C4DE86681E2171CF865B6F8EA828CD5  XnFreshDeploy.exe
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
