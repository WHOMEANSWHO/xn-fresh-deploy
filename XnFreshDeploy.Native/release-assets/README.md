# Xn Fresh Deploy 4.1

Xn Fresh Deploy is a real compiled Windows app for FiveM server profiles, safe soundpack/ReShade switching, server-only commands, and guided PC setup. It does not use PowerShell and does not require .NET to be installed separately.

## Start

1. Extract the complete ZIP to a writable folder such as Desktop, Documents, another drive, or a USB stick.
2. Double-click `XnFreshDeploy.exe`.
3. Keep the EXE, `config.json`, `servers.json`, `Library`, and `Drivers` together. Your profiles and library remain beside the app.

Windows may show a SmartScreen warning because this community build is not commercially code-signed. Verify the published SHA-256 before running a copy received from someone else.

## Server profiles

- Open the built-in **Library** section to drag and drop or import soundpack/ReShade folders or ZIPs.
- Multiple folders or ZIPs can be selected or dropped in one batch. If a selected parent contains several direct subfolders, the app asks whether every subfolder should become a separate pack.
- The folder or ZIP name becomes the pack name. Before completing the import, the app asks whether you want to rename it.
- Imports show file counts and types, warn about executables/scripts/DLLs, and never run imported pack files.
- Create a profile with a connect code, `cfx.re/join/...` link, IP, or hostname.
- Use **Detect from FiveM** after joining a server once to retrieve a recent connect code or endpoint from FiveM's own logs.
- Choose one soundpack and one ReShade look from the drop-downs.
- Click one server command, or hold Ctrl while clicking to select several. Custom commands can be added below the preset list.
- Click **Play** to stage packs, enforce FiveM Canary (Latest/Unstable), apply the chosen setup, and connect.

Close FiveM before switching packs or launching a profile with startup commands. Use **Restore previous** to swap back to the last working soundpack/ReShade setup.

## Backups and migration

- **Export** creates a small profile-assignment backup.
- **Full backup** includes profiles plus every referenced soundpack and ReShade look.
- **Import** previews and verifies full portable backups before copying their contents.

## PC Setup

PC Setup can install selected apps through winget, run local driver packages, adjust Windows mouse acceleration, download FiveM, open the official ReShade installer, and restore a portable PC backup. The everyday app runs normally; Windows administrator permission is requested only after you press **Start PC setup**. The main app stays open and continues showing progress while an invisible elevated worker performs administrator-only changes—no second app window is opened.

Downloaded FiveM installers must pass Windows signature and publisher checks. ReShade must pass Windows signature validation and match the current certificate thumbprint published on the official ReShade website.

## Requirements

- 64-bit Windows 10 or Windows 11
- Internet access for server checks and selected PC Setup downloads
- FiveM opened once before applying soundpacks or ReShade looks

Xn Fresh Deploy stores data portably beside the EXE. Do not run it from inside the ZIP or place it under `Program Files`.
