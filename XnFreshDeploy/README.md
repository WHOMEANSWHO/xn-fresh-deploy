# Xn Fresh Deploy

Xn Fresh Deploy is a portable Windows app for setting up a PC and launching FiveM servers with the correct soundpack and ReShade profile.

Version: 3.10

## Requirements

- 64-bit Windows 10 or Windows 11
- Windows PowerShell 5.1 (included with Windows)
- An internet connection for downloads, update checks, and server-status checks
- A writable extracted folder; do not run the app from inside the ZIP or from Program Files
- FiveM must be opened once before ReShade can be installed into it

The everyday server-profile and ReShade tools run without administrator access. Windows requests administrator permission only when a PC setup run starts.

## Quick start

1. Extract the complete `XnFreshDeploy` folder somewhere writable, such as Documents, Desktop, another drive, or a USB stick.
2. Double-click `Xn-Setup.bat`.
3. Open **PC setup**, review every switch, and select only the apps and changes you want.
4. Open **Server profiles** to add a server, soundpack, and ReShade look.

Keep every release file together. The app stores its configuration, profiles, libraries, and backups beside itself so the entire folder can be moved to another PC.

## Safer defaults

Only 7-Zip is selected by default in the optional app list because it is needed for automatic ReShade and archive handling. Other optional apps, detected driver helpers, mouse acceleration changes, driver packages, and automatic app launching require the user to select them. FiveM and ReShade remain visible setup choices and should still be reviewed before starting.

Use **All** only when you really want every optional app in `config.json`.

## Fresh PC setup

The PC setup screen can:

- Install selected apps through winget
- Detect graphics and CPU hardware and offer the appropriate driver helper
- Run driver packages placed in the `Drivers` folder
- Disable Windows mouse acceleration when selected
- Download FiveM
- Install ReShade for FiveM
- Restore browser bookmarks and FiveM settings from the local `Backup` folder
- Open selected apps after setup

Driver installers run one at a time. Supported files in `Drivers` are `.zip`, `.7z`, `.rar`, `.exe`, and `.msi`. The Drivers switch is enabled automatically only when a supported package is present.

ReShade can be installed only after FiveM has created `%LocalAppData%\FiveM\FiveM.app`. On a new PC, install and open FiveM once, close it, and then run the ReShade step or use ReShade manager.

Running PC setup again is safe. Existing managed ReShade installs are left to ReShade manager so they are not overwritten by the general setup workflow.

## Server profiles

Create one profile for each FiveM server. A profile stores:

- The profile name
- A Cfx.re join code, `cfx.re/join/...` link, or direct `IP:port`
- The soundpack to place in FiveM's `mods` folder
- The ReShade look to apply before connecting
- One or more server commands selected from the built-in command picker
- Favourite and last-played information

If a server gives you a short connect code, paste the code directly. Otherwise, join the server once and use **Detect from FiveM**. Detection prefers a recent join code, then a verified endpoint, then a recent logged address.

Use **Test connection** to check Online/Offline, retrieve the server name, and show player information when available. Direct endpoints are checked through FiveM's `info.json` and `dynamic.json`; join codes use the Cfx.re listing.

Saved profiles support Edit, Duplicate, Favourite, Remove, search, sorting, and managed desktop shortcuts. Cards show readiness states such as Ready, Server offline, Pack missing, ReShade missing, ReShade base missing, FiveM missing, or FiveM running.

**Apply and play** saves the current setup for rollback, applies the selected pack and look, verifies the result, and then connects. **Restore previous** swaps back to the exact previous soundpack and ReShade/plugins snapshot.

Fresh Deploy keeps FiveM on its **Latest (Unstable)** update channel (`canary`). The setting is checked at startup and immediately before every profile launch. This intentionally chooses newer, less-tested client updates; remove `UpdateChannel=canary` from `%LocalAppData%\FiveM\FiveM.app\CitizenFX.ini` only if you no longer want this behaviour.

Choose commands from the profile configurator or editor. A normal click chooses one command; hold **Ctrl** while clicking to select or remove several. The picker includes FPS, crosshair, brightness, aiming/mouse acceleration, mouse scale, first-person FOV, synchronous audio, and server-download options. Commands needing a number reveal their own value field, and conflicting Crosshair on/off choices cannot be enabled together.

Use **Add your own command** for an additional FiveM setting. Enter its command/convar name and value, then press **Add command**. It appears as a selected Custom entry in the same picker. Select Custom entries and press **Remove selected custom** to delete them. Custom names and values receive the same validation and are included in profile duplication, export/import, portable backups, and shortcuts.

Fresh Deploy validates the selection and starts FiveM with session-only `+set` arguments, followed by that profile's connection. FiveM must be fully closed before launching a profile that has commands. The settings last for that FiveM session, so close FiveM before manually changing to another server or launching a different configured profile.

## Pack library

Each subfolder is one reusable pack:

- `Library\Soundpacks\<name>\` contains files for FiveM's `mods` folder
- `Library\ReShade\<name>\` contains preset-specific ReShade files for one look

Use **Manage** to import folders with the picker or drag-and-drop. Import preview shows file count, size, and types before copying. Executables, scripts, DLLs, and ASI files receive a prominent warning.

The manager shows file counts and dependent profiles. Renaming a pack updates its profiles. Deleting warns about affected profiles and resets those assignments safely.

Soundpack changes are built in a temporary folder and checked with SHA-256 before swapping. Cached file metadata avoids re-hashing unchanged packs. ReShade looks track their own files so switching looks removes only the previous look's files.

## ReShade manager

Open **ReShade manager** from the Server profiles tab. It provides:

- Verified Install, Update, Repair/Reinstall, and managed uninstall
- Installed and latest version display
- DLL, configuration, shader, texture, and tracked-file health checks
- Preset checks for missing effects and textures
- Standard ReShade shaders plus optional SweetFX, qUINT, prod80, and custom folders
- Safe `dxgi.dll` and `d3d11.dll` switching
- Automatic FiveM acknowledgement detection and application
- A precise base-install manifest with original-file restoration

The current release and signing thumbprint are read from [reshade.me](https://reshade.me/). The installer is accepted only when its Windows signature matches that published thumbprint. Shader downloads come from their official repositories:

- [ReShade shaders](https://github.com/crosire/reshade-shaders)
- [SweetFX](https://github.com/CeeJayDK/SweetFX)
- [qUINT](https://github.com/martymcmodding/qUINT)
- [prod80](https://github.com/prod80/prod80-ReShade-Repository)

An existing external ReShade setup must be repaired once before the app can remove it precisely. Repair records the managed files and backs up anything it replaces.

Press Home in game to toggle the ReShade overlay.

## Backups and migration

Use **Export** for a small profile-assignment backup. Use **Full backup** to include every referenced soundpack and ReShade look in a verified portable ZIP. Import merges profiles and safely renames conflicting library items.

Before wiping Windows, use **Back up now** on PC setup. It saves supported browser bookmarks and the roaming CitizenFX folder beside the app. Passwords cannot be copied normally because Windows encrypts them for the old installation. Use browser sync or the app's **Export passwords** helper instead.

`ReShadePayload.zip` remains supported as a legacy complete ReShade restore. After restoration, use Repair in ReShade manager to bring its base files under precise management.

## Crash recovery and safety

File-changing operations use temporary stages, verification, rollback folders, and recovery journals. On startup, unfinished soundpack or ReShade work is restored to the last complete state.

Downloads are restricted to expected HTTPS hosts. FiveM, NVIDIA, and ReShade installers must pass publisher or certificate checks. Archives are validated before extraction, including path and expanded-size checks.

The app has no telemetry and does not upload your profiles, packs, or backups. It contacts download providers, Cfx.re/FiveM endpoints for requested status checks, and official update sources as described above.

## Customising the app list

Open **Edit app list** or edit `config.json`. Each entry supports:

- `name`: text shown in the app
- `desc`: short explanation
- `wingetId`: exact winget package ID
- `selectedByDefault`: whether its switch starts on
- `launchAfter`: whether it can open after setup
- `launchPaths`: possible executable paths

Find package IDs with `winget search <name>`. Invalid or duplicate entries produce a clear startup error instead of partially loading the setup screen.

## Sharing a clean copy

Share the generated `XnFreshDeploy-v3.10.zip`, not a working folder that contains personal profiles or packs. A clean release should have an empty `servers.json`, only the placeholder files in `Library` and `Drivers`, and no `Backup`, ReShade payload, integrity cache, or temporary files.

The PowerShell source is intentionally included so users can inspect what the app changes. Windows may warn about unsigned downloaded scripts; only use releases from a source you trust.

## Optional EXE wrapper

The BAT launcher is the supported portable entry point. An EXE wrapper is cosmetic and is not required. If you build one yourself, keep the original folder structure and test all relative paths before distributing it.
