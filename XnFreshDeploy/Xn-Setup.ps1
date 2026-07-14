# ==============================================================================
#  XN FRESH DEPLOY v3.10 - set up your PC + launch FiveM servers your way
#
#  Double-click Xn-Setup.bat to open the app.
#  Desktop shortcuts made by the Play tab run this with -Play "Server name".
# ==============================================================================

param(
    [string]$Play = '',
    [string]$RunSetup = ''
)

$ErrorActionPreference = 'Stop'

# The everyday profile UI runs normally. PC setup elevates only when it starts.
function Test-IsAdministrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$script:ScriptDir   = Split-Path -Parent $PSCommandPath
$script:ConfigPath  = Join-Path $ScriptDir 'config.json'
$script:ServersPath = Join-Path $ScriptDir 'servers.json'
$script:UserAgent   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) XnFreshDeploy/3.10'

# --- Library folders (soundpacks + ReShade looks live here, next to the app) ---
$script:LibraryDir    = Join-Path $ScriptDir 'Library'
$script:SoundLibDir   = Join-Path $LibraryDir 'Soundpacks'
$script:ReshadeLibDir = Join-Path $LibraryDir 'ReShade'
$script:IntegrityFileName = '.xn-integrity.json'
try {
    foreach ($d in $LibraryDir, $SoundLibDir, $ReshadeLibDir) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}
catch {
    [Windows.MessageBox]::Show("Xn Fresh Deploy cannot write to this folder.`n`nMove the whole XnFreshDeploy folder somewhere writable, such as Documents, Desktop, another drive, or a USB stick, then try again.`n`n$($_.Exception.Message)", 'Xn Fresh Deploy') | Out-Null
    exit 1
}

# --- Default config (created on first run, then yours to edit) -----------------
$DefaultConfig = @'
{
  "_help": "This is your app list. wingetId must be an exact winget package id. selectedByDefault controls its initial switch. desc is shown in the app. launchPaths are tried in order when opening apps at the end.",
  "apps": [
    { "name": "7-Zip",         "desc": "Unzips files - also needed for drivers and ReShade",
      "wingetId": "7zip.7zip",            "selectedByDefault": true, "launchAfter": false, "launchPaths": [] },
    { "name": "Brave Browser", "desc": "Your web browser",
      "wingetId": "Brave.Brave",          "selectedByDefault": false, "launchAfter": true,
      "launchPaths": ["%ProgramFiles%\\BraveSoftware\\Brave-Browser\\Application\\brave.exe"] },
    { "name": "Steam",         "desc": "Game launcher",
      "wingetId": "Valve.Steam",          "selectedByDefault": false, "launchAfter": true,
      "launchPaths": ["%ProgramFiles(x86)%\\Steam\\steam.exe"] },
    { "name": "Discord",       "desc": "Voice and chat",
      "wingetId": "Discord.Discord",      "selectedByDefault": false, "launchAfter": true,
      "launchPaths": ["%LocalAppData%\\Discord\\Update.exe"], "launchArgs": "--processStart Discord.exe" },
    { "name": "Cursor",        "desc": "Your code editor",
      "wingetId": "Anysphere.Cursor",     "selectedByDefault": false, "launchAfter": true,
      "launchPaths": ["%LocalAppData%\\Programs\\cursor\\Cursor.exe"] },
    { "name": "OBS Studio",    "desc": "Recording and streaming",
      "wingetId": "OBSProject.OBSStudio", "selectedByDefault": false, "launchAfter": false,
      "launchPaths": ["%ProgramFiles%\\obs-studio\\bin\\64bit\\obs64.exe"] },
    { "name": "Stremio",       "desc": "Movies and TV",
      "wingetId": "Stremio.Stremio",      "selectedByDefault": false, "launchAfter": true,
      "launchPaths": ["%LocalAppData%\\Programs\\LNV\\Stremio-4\\stremio.exe", "%AppData%\\stremio\\stremio.exe"] },
    { "name": "Git",           "desc": "Version control for code",
      "wingetId": "Git.Git",              "selectedByDefault": false, "launchAfter": false, "launchPaths": [] },
    { "name": "Node.js LTS",   "desc": "Needed for your dev tools",
      "wingetId": "OpenJS.NodeJS.LTS",    "selectedByDefault": false, "launchAfter": false, "launchPaths": [] }
  ],
  "fivem":   { "downloadUrl": "https://runtime.fivem.net/client/FiveM.exe" },
  "reshade": { "payloadZip": "ReShadePayload.zip", "installShaders": true },
  "driversFolder": "Drivers",
  "tweaks":  { "disableMouseAcceleration": true }
}
'@

try {
    if (-not (Test-Path $ConfigPath)) { $DefaultConfig | Set-Content -Path $ConfigPath -Encoding UTF8 }
    $script:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if ($null -eq $Config.apps) { throw 'The apps list is missing.' }
    $appNames = @{}
    foreach ($app in @($Config.apps)) {
        $name = ([string]$app.name).Trim()
        $wingetId = ([string]$app.wingetId).Trim()
        if (-not $name -or -not $wingetId) { throw 'Every app needs both a name and a wingetId.' }
        if ($wingetId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$') { throw "The wingetId for '$name' contains unsupported characters." }
        if ($appNames.ContainsKey($name)) { throw "The app name '$name' is listed more than once." }
        $appNames[$name] = $true
    }
    if (-not $Config.fivem -or -not $Config.fivem.downloadUrl) { throw 'The FiveM downloadUrl is missing.' }
}
catch {
    [Windows.MessageBox]::Show("config.json has a mistake in it:`n`n$($_.Exception.Message)`n`nFix it, or delete it and a fresh one will be created.", 'Xn Fresh Deploy') | Out-Null
    exit 1
}

# --- Servers list ---------------------------------------------------------------
if (-not (Test-Path $ServersPath)) {
    try { '{ "servers": [] }' | Set-Content -Path $ServersPath -Encoding UTF8 }
    catch {
        [Windows.MessageBox]::Show("Xn Fresh Deploy could not create servers.json. Make sure this folder is writable.`n`n$($_.Exception.Message)", 'Xn Fresh Deploy') | Out-Null
        exit 1
    }
}
$script:Servers = @()
try {
    $sj = Get-Content $ServersPath -Raw | ConvertFrom-Json
    if ($sj.servers) { $script:Servers = @($sj.servers) }
}
catch {
    [Windows.MessageBox]::Show("servers.json has a mistake in it - starting with an empty server list.`n`n$($_.Exception.Message)", 'Xn Fresh Deploy') | Out-Null
}

function Save-Servers {
    $temporary = $script:ServersPath + '.new-' + [Guid]::NewGuid().ToString('N')
    try {
        @{ servers = @($script:Servers) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporary -Encoding UTF8
        [void](Get-Content -LiteralPath $temporary -Raw | ConvertFrom-Json)
        Move-Item -LiteralPath $temporary -Destination $script:ServersPath -Force
    }
    finally { if (Test-Path $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

function Set-Prop($Obj, [string]$Name, $Value) {
    $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Test-LibraryName([string]$Name) {
    return [bool]($Name -match '^[\w \-\.]{1,30}$' -and $Name -notmatch '^[\._]')
}

$driversCfg = if ($Config.driversFolder) { [string]$Config.driversFolder } else { 'Drivers' }
$script:DriversDir = if ([IO.Path]::IsPathRooted($driversCfg)) { $driversCfg } else { Join-Path $ScriptDir $driversCfg }
if (-not (Test-Path $DriversDir)) { New-Item -ItemType Directory -Path $DriversDir -Force | Out-Null }

# ==============================================================================
#  Shared play engine (used by the Play tab AND desktop shortcuts)
# ==============================================================================
function Test-FiveMRunning {
    return [bool](Get-Process -Name 'FiveM*' -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-RelativeChildPath([string]$Root, [string]$FullName) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($FullName)
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped its expected folder: $FullName"
    }
    return $full.Substring($rootFull.Length)
}

function Get-EffectiveExclusions([string[]]$Names = @()) {
    return @(@($Names) + @($script:IntegrityFileName) | Where-Object { $_ } | Select-Object -Unique)
}

function Test-IsLibraryPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    foreach ($root in @($script:SoundLibDir, $script:ReshadeLibDir)) {
        if (-not $root) { continue }
        $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        if ($full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-SafeChildPath([string]$Root, [string]$RelativePath) {
    if (-not $RelativePath -or [IO.Path]::IsPathRooted($RelativePath)) { throw 'Invalid relative file path.' }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $target = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    if (-not $target.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe file path in profile: $RelativePath"
    }
    return $target
}

function Get-TreeStats([string]$Path, [string[]]$ExcludeLeafNames = @()) {
    if (-not (Test-Path $Path)) { return [pscustomobject]@{ Files = 0; Bytes = [int64]0 } }
    $ExcludeLeafNames = Get-EffectiveExclusions $ExcludeLeafNames
    $files = @(Get-ChildItem $Path -Recurse -Force -File -ErrorAction Stop |
               Where-Object { $ExcludeLeafNames -notcontains $_.Name })
    [int64]$bytes = 0
    foreach ($file in $files) { $bytes += $file.Length }
    return [pscustomobject]@{ Files = $files.Count; Bytes = $bytes }
}

function Copy-DirectoryContents([string]$Source, [string]$Destination, [string[]]$ExcludeLeafNames = @()) {
    if (-not (Test-Path $Source -PathType Container)) { throw "Source folder is missing: $Source" }
    $ExcludeLeafNames = Get-EffectiveExclusions $ExcludeLeafNames
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($file in Get-ChildItem $Source -Recurse -Force -File -ErrorAction Stop) {
        if ($ExcludeLeafNames -contains $file.Name) { continue }
        $relative = Get-RelativeChildPath $Source $file.FullName
        $target = Get-SafeChildPath $Destination $relative
        $parent = Split-Path -Parent $target
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force -ErrorAction Stop
    }
}

function Get-TreeHashManifest([string]$Path, [string[]]$ExcludeLeafNames = @(), [bool]$UseCache = $false, [bool]$WriteCache = $false) {
    if (-not (Test-Path $Path -PathType Container)) { throw "Folder is missing: $Path" }
    $ExcludeLeafNames = Get-EffectiveExclusions $ExcludeLeafNames
    $files = @(Get-ChildItem $Path -Recurse -Force -File -ErrorAction Stop |
               Where-Object { $ExcludeLeafNames -notcontains $_.Name } | Sort-Object FullName)
    $cachePath = Join-Path $Path $script:IntegrityFileName

    if ($UseCache -and (Test-Path $cachePath -PathType Leaf)) {
        try {
            $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
            $cachedFiles = @($cache.files)
            if ([int]$cache.version -ne 1 -or $cachedFiles.Count -ne $files.Count) { throw 'Cache shape changed.' }
            $byPath = @{}
            foreach ($entry in $cachedFiles) { $byPath[[string]$entry.path] = $entry }
            $valid = $true
            foreach ($file in $files) {
                $relative = Get-RelativeChildPath $Path $file.FullName
                $entry = $byPath[$relative]
                if (-not $entry -or [int64]$entry.length -ne $file.Length -or
                    [int64]$entry.lastWriteUtcTicks -ne $file.LastWriteTimeUtc.Ticks -or
                    [string]$entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { $valid = $false; break }
            }
            if ($valid) {
                return @($cachedFiles | ForEach-Object {
                    [pscustomobject]@{ Path = [string]$_.path; Length = [int64]$_.length; LastWriteUtcTicks = [int64]$_.lastWriteUtcTicks; SHA256 = ([string]$_.sha256).ToUpperInvariant() }
                })
            }
        }
        catch {}
    }

    $manifest = New-Object System.Collections.ArrayList
    foreach ($file in $files) {
        [void]$manifest.Add([pscustomobject]@{
            Path = Get-RelativeChildPath $Path $file.FullName
            Length = [int64]$file.Length
            LastWriteUtcTicks = [int64]$file.LastWriteTimeUtc.Ticks
            SHA256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        })
    }
    if ($WriteCache) {
        [ordered]@{
            version = 1
            generatedAt = [DateTime]::UtcNow.ToString('o')
            files = @($manifest | ForEach-Object {
                [ordered]@{ path = $_.Path; length = $_.Length; lastWriteUtcTicks = $_.LastWriteUtcTicks; sha256 = $_.SHA256 }
            })
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $cachePath -Encoding UTF8
    }
    return @($manifest)
}

function Assert-TreesMatch([string]$Expected, [string]$Actual, [string[]]$ExcludeLeafNames = @(), [bool]$VerifyHashes = $true) {
    $ExcludeLeafNames = Get-EffectiveExclusions $ExcludeLeafNames
    $a = Get-TreeStats $Expected $ExcludeLeafNames
    $b = Get-TreeStats $Actual $ExcludeLeafNames
    if ($a.Files -ne $b.Files -or $a.Bytes -ne $b.Bytes) {
        throw "Copy verification failed ($($a.Files) files/$($a.Bytes) bytes expected; $($b.Files) files/$($b.Bytes) bytes copied)."
    }
    $expectedHashes = @{}
    if ($VerifyHashes) {
        $cacheExpected = Test-IsLibraryPath $Expected
        foreach ($entry in @(Get-TreeHashManifest $Expected $ExcludeLeafNames $cacheExpected $cacheExpected)) { $expectedHashes[$entry.Path] = $entry.SHA256 }
    }
    foreach ($expectedFile in Get-ChildItem $Expected -Recurse -Force -File -ErrorAction Stop |
             Where-Object { $ExcludeLeafNames -notcontains $_.Name }) {
        $relative = Get-RelativeChildPath $Expected $expectedFile.FullName
        $actualFile = Get-SafeChildPath $Actual $relative
        if (-not (Test-Path $actualFile -PathType Leaf)) { throw "Copy verification failed: $relative is missing." }
        if ($expectedFile.Length -ne (Get-Item $actualFile).Length) { throw "Copy verification failed: $relative has the wrong size." }
        if ($VerifyHashes) {
            $expectedHash = [string]$expectedHashes[$relative]
            $actualHash = (Get-FileHash -LiteralPath $actualFile -Algorithm SHA256).Hash
            if ($expectedHash -ne $actualHash) { throw "Copy verification failed: $relative did not copy exactly." }
        }
    }
}

function Apply-Soundpack([string]$PackName) {
    if (-not $PackName) { $PackName = 'None' }
    $isOriginalBackup = ($PackName -eq '__original__')
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    if (-not (Test-Path $appDir)) { throw "FiveM isn't installed yet - run 'PC setup' first." }
    $mods = Join-Path $appDir 'mods'
    $marker = Join-Path $mods '.xn-current'
    $current = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { $null }
    if ($current -eq $PackName) { return }

    $source = $null
    if ($PackName -ne 'None') {
        if ($isOriginalBackup) { $source = Join-Path $script:SoundLibDir '_LastReplaced' }
        else {
            if (-not (Test-LibraryName $PackName)) { throw 'The selected soundpack name is unsafe.' }
            $source = Get-SafeChildPath $script:SoundLibDir $PackName
        }
        if (-not (Test-Path $source -PathType Container)) { throw "Soundpack '$PackName' is missing from the library." }
        $sourceStats = Get-TreeStats $source @('.xn-current')
        if ($sourceStats.Files -eq 0) { throw "Soundpack '$PackName' is empty." }
    }

    $id = [Guid]::NewGuid().ToString('N')
    $stage = Join-Path $appDir ".xn-mods-stage-$id"
    $rollback = Join-Path $appDir ".xn-mods-rollback-$id"
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    try {
        if ($source) {
            Copy-DirectoryContents $source $stage @('.xn-current')
            Assert-TreesMatch $source $stage @('.xn-current')
        }
        Set-Content -Path (Join-Path $stage '.xn-current') -Value $PackName -Encoding ASCII

        # Preserve the first unmanaged mods folder using the same verified-copy approach.
        $existing = if (Test-Path $mods) {
            @(Get-ChildItem $mods -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.xn-current' })
        } else { @() }
        if ($existing.Count -gt 0 -and -not $current -and -not $isOriginalBackup) {
            $backup = Join-Path $script:SoundLibDir '_LastReplaced'
            $backupStage = Join-Path $script:SoundLibDir "_LastReplaced-stage-$id"
            try {
                Copy-DirectoryContents $mods $backupStage @('.xn-current')
                Assert-TreesMatch $mods $backupStage @('.xn-current')
                if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
                Move-Item -LiteralPath $backupStage -Destination $backup -Force
            }
            finally {
                if (Test-Path $backupStage) { Remove-Item $backupStage -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        if (Test-Path $mods) { Move-Item -LiteralPath $mods -Destination $rollback -Force }
        try {
            Move-Item -LiteralPath $stage -Destination $mods -Force
            if ($source) { Assert-TreesMatch $source $mods @('.xn-current') $false }
            else {
                $emptyStats = Get-TreeStats $mods @('.xn-current')
                if ($emptyStats.Files -ne 0) { throw 'The empty soundpack stage contained unexpected files.' }
            }
        }
        catch {
            if (Test-Path $mods) { Remove-Item $mods -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $rollback) { Move-Item -LiteralPath $rollback -Destination $mods -Force }
            throw
        }

        if (Test-Path $rollback) { Remove-Item $rollback -Recurse -Force }
    }
    finally {
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
        if ((Test-Path $rollback) -and -not (Test-Path $mods)) {
            Move-Item -LiteralPath $rollback -Destination $mods -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ReShadePaths {
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    $plugins = Join-Path $appDir 'plugins'
    return [pscustomobject]@{
        AppDir = $appDir
        Plugins = $plugins
        Manifest = Join-Path $plugins '.xn-reshade-base.json'
        Backup = Join-Path $appDir '.xn-reshade-base-backup'
    }
}

function Get-ReShadeBaseManifest {
    $paths = Get-ReShadePaths
    if (-not (Test-Path $paths.Manifest -PathType Leaf)) { return $null }
    try {
        $manifest = Get-Content -LiteralPath $paths.Manifest -Raw | ConvertFrom-Json
        if ([int]$manifest.version -ne 1) { return $null }
        return $manifest
    }
    catch { return $null }
}

function Get-ReShadeBaseProtectedFiles {
    $manifest = Get-ReShadeBaseManifest
    if (-not $manifest) { return @() }
    return @($manifest.files | ForEach-Object { [string]$_.path } | Where-Object { $_ } | Select-Object -Unique)
}

function Save-ReShadeBaseManifest($Manifest) {
    $paths = Get-ReShadePaths
    New-Item -ItemType Directory -Path $paths.Plugins -Force | Out-Null
    $temporary = $paths.Manifest + '.new-' + [Guid]::NewGuid().ToString('N')
    try {
        $Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
        [void](Get-Content -LiteralPath $temporary -Raw | ConvertFrom-Json)
        Move-Item -LiteralPath $temporary -Destination $paths.Manifest -Force
    }
    finally {
        if (Test-Path $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Assert-ReShadeManagerUrl([string]$Url, [string[]]$AllowedHosts, [string]$Label) {
    try { $uri = [Uri]$Url } catch { throw "$Label has an invalid download address." }
    if ($uri.Scheme -ne 'https' -or $AllowedHosts -notcontains $uri.DnsSafeHost) {
        throw "$Label download was blocked because it did not come from an approved HTTPS address."
    }
}

function Assert-ReShadeManagerZip([string]$Path, [string]$Label) {
    $archive = $null
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($Path)
        if ($archive.Entries.Count -eq 0) { throw "$Label is empty." }
        if ($archive.Entries.Count -gt 100000) { throw "$Label contains too many files." }
        [int64]$expandedBytes = 0
        foreach ($entry in $archive.Entries) {
            $name = ([string]$entry.FullName).Replace('/', '\')
            if ([IO.Path]::IsPathRooted($name) -or $name -match '(^|\\)\.\.(\\|$)') {
                throw "$Label contains an unsafe file path."
            }
            $expandedBytes += [int64]$entry.Length
            if ($expandedBytes -gt 5GB) { throw "$Label is unexpectedly large." }
        }
    }
    catch {
        if ($_.Exception.Message -like "$Label*") { throw }
        throw "$Label is not a valid ZIP archive."
    }
    finally { if ($archive) { $archive.Dispose() } }
}

function Get-ReShadeOfficialInfo {
    $home = 'https://reshade.me'
    Assert-ReShadeManagerUrl $home @('reshade.me') 'ReShade website'
    $html = (Invoke-WebRequest -Uri $home -UseBasicParsing -TimeoutSec 20 -UserAgent $script:UserAgent).Content
    $version = $null; $thumbprint = $null
    if ($html -match '/downloads/ReShade_Setup_(\d+\.\d+\.\d+)\.exe') { $version = $Matches[1] }
    if ($html -match '(?is)X\.509 Digital Signature Thumbprint:.{0,250}?([A-Fa-f0-9]{40})') { $thumbprint = $Matches[1].ToUpperInvariant() }
    if (-not $version -or -not $thumbprint) { throw 'The official ReShade page changed, so the safe download check stopped the install.' }
    return [pscustomobject]@{
        Version = $version
        Thumbprint = $thumbprint
        DownloadUrl = "https://reshade.me/downloads/ReShade_Setup_$version.exe"
    }
}

function Assert-OfficialReShadeSetup([string]$Path, [string]$Thumbprint) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
        throw 'The ReShade installer does not have a valid Windows signature.'
    }
    if ([string]$signature.SignerCertificate.Thumbprint -ine $Thumbprint) {
        throw 'The ReShade installer signature does not match the thumbprint published on reshade.me.'
    }
}

function Get-ReShadeShaderPackDefinitions {
    return [ordered]@{
        Standard = 'https://github.com/crosire/reshade-shaders/archive/refs/heads/slim.zip'
        SweetFX  = 'https://github.com/CeeJayDK/SweetFX/archive/refs/heads/master.zip'
        qUINT    = 'https://github.com/martymcmodding/qUINT/archive/refs/heads/master.zip'
        prod80   = 'https://github.com/prod80/prod80-ReShade-Repository/archive/refs/heads/master.zip'
    }
}

function Copy-ReShadeShaderSource([string]$Source, [string]$Stage, [string]$SourceLabel, [hashtable]$SourceMap) {
    $shaderRoot = Join-Path $Stage 'reshade-shaders\Shaders'
    $textureRoot = Join-Path $Stage 'reshade-shaders\Textures'
    New-Item -ItemType Directory -Path $shaderRoot,$textureRoot -Force | Out-Null
    $copied = 0
    foreach ($kind in 'Shaders','Textures') {
        $destRoot = if ($kind -eq 'Shaders') { $shaderRoot } else { $textureRoot }
        $folders = @(Get-ChildItem -LiteralPath $Source -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -eq $kind })
        $top = @(Get-ChildItem -LiteralPath $Source -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $kind })
        if ($top.Count -gt 0) { $folders = $top }
        foreach ($folder in $folders) {
            foreach ($file in Get-ChildItem -LiteralPath $folder.FullName -File -Recurse -Force -ErrorAction Stop) {
                $relative = Get-RelativeChildPath $folder.FullName $file.FullName
                $target = Get-SafeChildPath $destRoot $relative
                $parent = Split-Path -Parent $target
                if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $file.FullName -Destination $target -Force
                $SourceMap[(Get-RelativeChildPath $Stage $target)] = $SourceLabel
                $copied++
            }
        }
    }
    if ($copied -eq 0) {
        foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse -Force -ErrorAction Stop) {
            $extension = $file.Extension.ToLowerInvariant()
            $destRoot = if ($extension -in '.fx','.fxh') { $shaderRoot } elseif ($extension -in '.png','.jpg','.jpeg','.dds','.bmp') { $textureRoot } else { $null }
            if (-not $destRoot) { continue }
            $target = Join-Path $destRoot $file.Name
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            $SourceMap[(Get-RelativeChildPath $Stage $target)] = $SourceLabel
            $copied++
        }
    }
    if ($copied -eq 0) { throw "$SourceLabel did not contain a Shaders or Textures folder, .fx effects, or texture files." }
    return $copied
}

function Get-ReShadeIniContent([string]$ExistingPath) {
    $content = if (Test-Path $ExistingPath -PathType Leaf) { Get-Content -LiteralPath $ExistingPath -Raw } else { "[GENERAL]`r`n" }
    if ($content -notmatch '(?im)^\[GENERAL\]\s*$') { $content = "[GENERAL]`r`n" + $content }
    $settings = [ordered]@{
        EffectSearchPaths = '.\reshade-shaders\Shaders'
        TextureSearchPaths = '.\reshade-shaders\Textures'
    }
    foreach ($key in $settings.Keys) {
        $line = "$key=$($settings[$key])"
        if ($content -match "(?im)^$([regex]::Escape($key))=.*$") {
            $content = [regex]::Replace($content, "(?im)^$([regex]::Escape($key))=.*$", $line, 1)
        }
        else {
            $content = [regex]::Replace($content, '(?im)^\[GENERAL\]\s*$', "[GENERAL]`r`n$line", 1)
        }
    }
    return $content.TrimEnd() + "`r`n"
}

function Get-ReShadeInstalledVersion {
    $paths = Get-ReShadePaths
    foreach ($name in 'dxgi.dll','d3d11.dll') {
        $dll = Join-Path $paths.Plugins $name
        if (Test-Path $dll -PathType Leaf) {
            try {
                $version = (Get-Item -LiteralPath $dll).VersionInfo.ProductVersion
                if (-not $version) { $version = (Get-Item -LiteralPath $dll).VersionInfo.FileVersion }
                if ($version -match '\d+\.\d+(?:\.\d+)?') { return $Matches[0] }
            } catch {}
        }
    }
    $manifest = Get-ReShadeBaseManifest
    if ($manifest -and $manifest.installedVersion) { return [string]$manifest.installedVersion }
    return $null
}

function Test-ReShadePresetCompatibility {
    $paths = Get-ReShadePaths
    $shaderNames = @{}; $textureNames = @{}
    $shaderRoot = Join-Path $paths.Plugins 'reshade-shaders\Shaders'
    $textureRoot = Join-Path $paths.Plugins 'reshade-shaders\Textures'
    if (Test-Path $shaderRoot) {
        foreach ($file in Get-ChildItem $shaderRoot -File -Recurse -ErrorAction SilentlyContinue) {
            if ($file.Extension -ieq '.fx') { $shaderNames[$file.Name.ToLowerInvariant()] = $true }
        }
    }
    if (Test-Path $textureRoot) {
        foreach ($file in Get-ChildItem $textureRoot -File -Recurse -ErrorAction SilentlyContinue) { $textureNames[$file.Name.ToLowerInvariant()] = $true }
    }

    $presets = @()
    foreach ($root in @($paths.Plugins,$script:ReshadeLibDir)) {
        if (-not (Test-Path $root -PathType Container)) { continue }
        foreach ($file in Get-ChildItem $root -File -Filter '*.ini' -Recurse -ErrorAction SilentlyContinue) {
            if ($file.Name -ieq 'ReShade.ini') { continue }
            try {
                $raw = Get-Content -LiteralPath $file.FullName -Raw
                if ($raw -match '(?im)^(Techniques|TechniqueSorting|PreprocessorDefinitions)=') { $presets += [pscustomobject]@{ File=$file; Raw=$raw } }
            } catch {}
        }
    }
    $missingShaders = @()
    foreach ($preset in $presets) {
        foreach ($match in [regex]::Matches($preset.Raw, '@([^,\r\n]+?\.fx)')) {
            $leaf = [IO.Path]::GetFileName($match.Groups[1].Value.Trim())
            if ($leaf -and -not $shaderNames.ContainsKey($leaf.ToLowerInvariant())) { $missingShaders += $leaf }
        }
    }
    $missingTextures = @()
    if (Test-Path $shaderRoot) {
        foreach ($file in Get-ChildItem $shaderRoot -File -Include '*.fx','*.fxh' -Recurse -ErrorAction SilentlyContinue) {
            try {
                $raw = Get-Content -LiteralPath $file.FullName -Raw
                foreach ($match in [regex]::Matches($raw, '(?im)\bsource\s*=\s*"([^"\r\n]+\.(?:png|jpe?g|dds|bmp))"')) {
                    $leaf = [IO.Path]::GetFileName($match.Groups[1].Value)
                    if ($leaf -and -not $textureNames.ContainsKey($leaf.ToLowerInvariant())) { $missingTextures += $leaf }
                }
            } catch {}
        }
    }
    $missingShaders = @($missingShaders | Sort-Object -Unique)
    $missingTextures = @($missingTextures | Sort-Object -Unique)
    return [pscustomobject]@{
        PresetCount = $presets.Count
        MissingShaders = $missingShaders
        MissingTextures = $missingTextures
        Ready = ($missingShaders.Count -eq 0 -and $missingTextures.Count -eq 0)
    }
}

function Get-ReShadeHealth {
    $paths = Get-ReShadePaths
    $issues = @(); $modified = @(); $missing = @()
    $dxgi = Test-Path (Join-Path $paths.Plugins 'dxgi.dll') -PathType Leaf
    $d3d11 = Test-Path (Join-Path $paths.Plugins 'd3d11.dll') -PathType Leaf
    $mode = if ($dxgi -and $d3d11) { 'Conflict' } elseif ($d3d11) { 'd3d11.dll' } elseif ($dxgi) { 'dxgi.dll' } else { 'Not installed' }
    if (-not (Test-Path $paths.AppDir -PathType Container)) { $issues += 'FiveM has not been opened on this PC yet.' }
    elseif (-not ($dxgi -or $d3d11)) { $issues += 'The ReShade DLL is missing.' }
    if ($dxgi -and $d3d11) { $issues += 'Both dxgi.dll and d3d11.dll are present; keep only one ReShade DLL mode.' }
    $manifest = Get-ReShadeBaseManifest
    if ((Test-Path $paths.Manifest) -and -not $manifest) { $issues += 'The managed-install manifest is damaged.' }
    if (-not $manifest -and ($dxgi -or $d3d11)) { $issues += 'This is an older or external install; Repair can bring it under safe management.' }
    $manifestMetadataChanged = $false
    if ($manifest) {
        foreach ($entry in @($manifest.files)) {
            try { $target = Get-SafeChildPath $paths.Plugins ([string]$entry.path) } catch { $missing += [string]$entry.path; continue }
            if (-not (Test-Path $target -PathType Leaf)) { $missing += [string]$entry.path; continue }
            try {
                $item = Get-Item -LiteralPath $target
                if ([int64]$entry.length -ne $item.Length) {
                    $modified += [string]$entry.path
                }
                elseif ($entry.PSObject.Properties['lastWriteUtcTicks'] -and [int64]$entry.lastWriteUtcTicks -eq $item.LastWriteTimeUtc.Ticks) { continue }
                elseif ([string]$entry.sha256 -ine (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) { $modified += [string]$entry.path }
                else {
                    Set-Prop $entry 'lastWriteUtcTicks' ([int64]$item.LastWriteTimeUtc.Ticks)
                    $manifestMetadataChanged = $true
                }
            } catch { $modified += [string]$entry.path }
        }
        if ($manifestMetadataChanged) { try { Save-ReShadeBaseManifest $manifest } catch {} }
    }
    if ($missing.Count -gt 0) { $issues += "$($missing.Count) managed file(s) are missing." }
    if ($modified.Count -gt 0) { $issues += "$($modified.Count) managed file(s) changed after installation." }
    $iniPath = Join-Path $paths.Plugins 'ReShade.ini'
    if (-not (Test-Path $iniPath -PathType Leaf)) { $issues += 'ReShade.ini is missing.' }
    else {
        $ini = Get-Content -LiteralPath $iniPath -Raw -ErrorAction SilentlyContinue
        if ($ini -notmatch '(?im)^EffectSearchPaths=.*reshade-shaders[\\/]Shaders') { $issues += 'The shader search path needs repair.' }
        if ($ini -notmatch '(?im)^TextureSearchPaths=.*reshade-shaders[\\/]Textures') { $issues += 'The texture search path needs repair.' }
    }
    $shaderCount = @(Get-ChildItem (Join-Path $paths.Plugins 'reshade-shaders\Shaders') -File -Filter '*.fx' -Recurse -ErrorAction SilentlyContinue).Count
    $textureCount = @(Get-ChildItem (Join-Path $paths.Plugins 'reshade-shaders\Textures') -File -Recurse -ErrorAction SilentlyContinue).Count
    if (($dxgi -or $d3d11) -and $shaderCount -eq 0) { $issues += 'No shader effects are installed.' }
    $compatibility = Test-ReShadePresetCompatibility
    if (-not $compatibility.Ready) { $issues += 'One or more presets reference missing shaders or textures.' }
    return [pscustomobject]@{
        Ready = ($issues.Count -eq 0)
        Status = if ($issues.Count -eq 0) { 'Healthy' } elseif (-not ($dxgi -or $d3d11)) { 'Not installed' } else { 'Needs attention' }
        Version = Get-ReShadeInstalledVersion
        DllMode = $mode
        ShaderCount = $shaderCount
        TextureCount = $textureCount
        Issues = @($issues)
        Missing = @($missing)
        Modified = @($modified)
        Compatibility = $compatibility
        Manifest = $manifest
    }
}

function Get-FiveMReShadeAcknowledgement {
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app\logs'),
        (Join-Path $env:LOCALAPPDATA 'FiveM\FiveM Application Data\logs'),
        (Join-Path $env:APPDATA 'CitizenFX')
    )
    $files = @()
    foreach ($root in $roots) {
        if (Test-Path $root -PathType Container) {
            $files += Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
                      Where-Object { $_.Extension -in '.log','.txt','.ini' }
        }
    }
    foreach ($file in @($files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 100)) {
        try {
            $match = Select-String -LiteralPath $file.FullName -Pattern 'ReShade5=ID:[A-Za-z0-9_-]+\s+acknowledged' -AllMatches -ErrorAction Stop | Select-Object -Last 1
            if ($match) { return $match.Matches[$match.Matches.Count - 1].Value }
        } catch {}
    }
    return $null
}

function Get-CitizenFxIniPath {
    $candidates = @(
        (Join-Path $env:APPDATA 'CitizenFX\CitizenFX.ini'),
        (Join-Path $env:LOCALAPPDATA 'FiveM\FiveM Application Data\CitizenFX.ini'),
        (Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app\CitizenFX.ini')
    )
    foreach ($candidate in $candidates) { if (Test-Path $candidate -PathType Leaf) { return $candidate } }
    return $candidates[0]
}

function Set-FiveMReShadeAcknowledgement([string]$Acknowledgement) {
    if ($Acknowledgement -notmatch '^ReShade5=ID:[A-Za-z0-9_-]+\s+acknowledged$') { throw 'No valid ReShade acknowledgement line was found.' }
    if (Test-FiveMRunning) { throw 'Close FiveM before applying its ReShade acknowledgement.' }
    $path = Get-CitizenFxIniPath
    $parent = Split-Path -Parent $path
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $content = if (Test-Path $path) { Get-Content -LiteralPath $path -Raw } else { '' }
    if (Test-Path $path) { Copy-Item -LiteralPath $path -Destination ($path + '.xn-before-ack') -Force }
    if ($content -match '(?im)^ReShade5=ID:[^\r\n]+$') {
        $content = [regex]::Replace($content, '(?im)^ReShade5=ID:[^\r\n]+$', $Acknowledgement, 1)
    }
    elseif ($content -match '(?im)^\[Addons\]\s*$') {
        $content = [regex]::Replace($content, '(?im)^\[Addons\]\s*$', "[Addons]`r`n$Acknowledgement", 1)
    }
    else { $content = $content.TrimEnd() + "`r`n`r`n[Addons]`r`n$Acknowledgement`r`n" }
    $temp = $path + '.new-' + [Guid]::NewGuid().ToString('N')
    try {
        Set-Content -LiteralPath $temp -Value $content -Encoding ASCII
        Move-Item -LiteralPath $temp -Destination $path -Force
    }
    finally { if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } }
    return $path
}

function Install-ReShadeManaged([string[]]$ShaderPacks = @('Standard'), [string]$DllMode = 'dxgi.dll', [string[]]$CustomFolders = @()) {
    if (Test-FiveMRunning) { throw 'Close FiveM before installing or repairing ReShade.' }
    if ($DllMode -notin 'dxgi.dll','d3d11.dll') { throw 'Choose dxgi.dll or d3d11.dll for the ReShade DLL mode.' }
    $paths = Get-ReShadePaths
    if (-not (Test-Path $paths.AppDir -PathType Container)) { throw "FiveM has to be opened once before ReShade can be installed." }
    $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
    if (-not (Test-Path $sevenZip -PathType Leaf)) { throw '7-Zip is needed for the verified automatic install. Turn it on in PC setup, install it, then try again.' }
    $definitions = Get-ReShadeShaderPackDefinitions
    $ShaderPacks = @($ShaderPacks | Where-Object { $definitions.Contains($_) } | Select-Object -Unique)
    $CustomFolders = @($CustomFolders | Where-Object { $_ -and (Test-Path $_ -PathType Container) } | Select-Object -Unique)
    New-Item -ItemType Directory -Path $paths.Plugins,$paths.Backup -Force | Out-Null

    $work = Join-Path $env:TEMP ('XnReShadeManager-' + [Guid]::NewGuid().ToString('N'))
    $stage = Join-Path $work 'stage'
    $downloads = Join-Path $work 'downloads'
    $unpack = Join-Path $work 'unpack'
    $transactionId = [Guid]::NewGuid().ToString('N')
    $rollback = Join-Path $paths.AppDir ".xn-reshade-manager-rollback-$transactionId"
    $journal = Join-Path $paths.AppDir '.xn-reshade-base-journal.json'
    $sourceMap = @{}
    $newBackupRoots = @()
    $keepRecovery = $false
    $oldManifest = Get-ReShadeBaseManifest
    $oldManifestRaw = if (Test-Path $paths.Manifest) { Get-Content -LiteralPath $paths.Manifest -Raw } else { $null }
    try {
        New-Item -ItemType Directory -Path $stage,$downloads,$unpack -Force | Out-Null
        $official = Get-ReShadeOfficialInfo
        $setup = Join-Path $downloads "ReShade_Setup_$($official.Version).exe"
        Assert-ReShadeManagerUrl $official.DownloadUrl @('reshade.me') 'ReShade'
        Invoke-WebRequest -Uri $official.DownloadUrl -OutFile $setup -UseBasicParsing -TimeoutSec 90 -UserAgent $script:UserAgent
        Assert-OfficialReShadeSetup $setup $official.Thumbprint
        $dllOut = Join-Path $unpack 'dll'
        New-Item -ItemType Directory -Path $dllOut -Force | Out-Null
        & $sevenZip e $setup "-o$dllOut" 'ReShade64.dll' -y | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $dllOut 'ReShade64.dll') -PathType Leaf)) {
            throw 'The signed ReShade installer did not contain the expected 64-bit DLL.'
        }
        Copy-Item -LiteralPath (Join-Path $dllOut 'ReShade64.dll') -Destination (Join-Path $stage $DllMode) -Force
        $sourceMap[$DllMode] = 'ReShade'

        foreach ($pack in $ShaderPacks) {
            $url = [string]$definitions[$pack]
            Assert-ReShadeManagerUrl $url @('github.com') "$pack shader pack"
            $zip = Join-Path $downloads "$pack.zip"
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 90 -UserAgent $script:UserAgent
            Assert-ReShadeManagerZip $zip "$pack shader pack"
            $packRoot = Join-Path $unpack $pack
            New-Item -ItemType Directory -Path $packRoot -Force | Out-Null
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $packRoot)
            [void](Copy-ReShadeShaderSource $packRoot $stage $pack $sourceMap)
        }
        foreach ($custom in $CustomFolders) {
            [void](Copy-ReShadeShaderSource $custom $stage ("Custom:" + (Split-Path $custom -Leaf)) $sourceMap)
        }
        $iniStage = Join-Path $stage 'ReShade.ini'
        Set-Content -LiteralPath $iniStage -Value (Get-ReShadeIniContent (Join-Path $paths.Plugins 'ReShade.ini')) -Encoding UTF8
        $sourceMap['ReShade.ini'] = 'Manager settings'

        $newFiles = @(Get-ChildItem -LiteralPath $stage -File -Recurse -Force | ForEach-Object { Get-RelativeChildPath $stage $_.FullName })
        if ($newFiles.Count -lt 2) { throw 'The ReShade install stage is incomplete.' }
        $oldEntries = @{}
        if ($oldManifest) { foreach ($entry in @($oldManifest.files)) { $oldEntries[[string]$entry.path] = $entry } }
        $affected = @(@($oldEntries.Keys) + $newFiles | Select-Object -Unique)
        $existing = @()
        New-Item -ItemType Directory -Path $rollback -Force | Out-Null
        foreach ($relative in $affected) {
            $target = Get-SafeChildPath $paths.Plugins $relative
            if (Test-Path $target -PathType Leaf) {
                $backupTarget = Get-SafeChildPath $rollback $relative
                $parent = Split-Path -Parent $backupTarget
                if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $target -Destination $backupTarget -Force
                $existing += $relative
            }
        }
        [ordered]@{
            version = 1; rollbackFolder = Split-Path $rollback -Leaf
            affected = @($affected); existing = @($existing)
            hasOldManifest = ($null -ne $oldManifestRaw)
            oldManifestBase64 = if ($null -ne $oldManifestRaw) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($oldManifestRaw)) } else { '' }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journal -Encoding UTF8

        $entries = New-Object System.Collections.ArrayList
        foreach ($relative in $newFiles) {
            $stageFile = Get-SafeChildPath $stage $relative
            $stageItem = Get-Item -LiteralPath $stageFile
            $target = Get-SafeChildPath $paths.Plugins $relative
            $oldEntry = $oldEntries[$relative]
            $backupRelative = if ($oldEntry -and $oldEntry.backup) { [string]$oldEntry.backup } else { '' }
            if (-not $oldEntry -and (Test-Path $target -PathType Leaf)) {
                $backupRelative = "$transactionId\$relative"
                $original = Get-SafeChildPath $paths.Backup $backupRelative
                $parent = Split-Path -Parent $original
                if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $target -Destination $original -Force
                $newBackupRoots += (Join-Path $paths.Backup $transactionId)
            }
            [void]$entries.Add([ordered]@{
                path = $relative
                length = [int64]$stageItem.Length
                lastWriteUtcTicks = [int64]$stageItem.LastWriteTimeUtc.Ticks
                sha256 = (Get-FileHash -LiteralPath $stageFile -Algorithm SHA256).Hash
                source = if ($sourceMap.ContainsKey($relative)) { [string]$sourceMap[$relative] } else { 'Shader pack' }
                backup = $backupRelative
            })
        }

        foreach ($relative in $affected) {
            $target = Get-SafeChildPath $paths.Plugins $relative
            if (Test-Path $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
        }
        foreach ($oldRelative in @($oldEntries.Keys | Where-Object { $newFiles -notcontains $_ })) {
            $entry = $oldEntries[$oldRelative]
            if ($entry.backup) {
                $original = Get-SafeChildPath $paths.Backup ([string]$entry.backup)
                if (Test-Path $original -PathType Leaf) {
                    $target = Get-SafeChildPath $paths.Plugins $oldRelative
                    $parent = Split-Path -Parent $target
                    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    Copy-Item -LiteralPath $original -Destination $target -Force
                }
            }
        }
        Copy-DirectoryContents $stage $paths.Plugins
        foreach ($entry in $entries) {
            $target = Get-SafeChildPath $paths.Plugins ([string]$entry.path)
            $targetItem = Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
            if (-not $targetItem -or [int64]$entry.length -ne $targetItem.Length -or
                [string]$entry.sha256 -ine (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
                throw "ReShade install verification failed for $($entry.path)."
            }
            $entry.lastWriteUtcTicks = [int64]$targetItem.LastWriteTimeUtc.Ticks
        }
        $manifest = [ordered]@{
            version = 1
            installedVersion = [string]$official.Version
            installedAt = [DateTime]::UtcNow.ToString('o')
            dllMode = $DllMode
            shaderPacks = @($ShaderPacks)
            customSources = @($CustomFolders)
            files = @($entries)
        }
        Save-ReShadeBaseManifest $manifest
        Remove-Item -LiteralPath $journal -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $rollback -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($oldRelative in @($oldEntries.Keys | Where-Object { $newFiles -notcontains $_ })) {
            $entry = $oldEntries[$oldRelative]
            if ($entry.backup) {
                $original = Get-SafeChildPath $paths.Backup ([string]$entry.backup)
                if (Test-Path $original -PathType Leaf) { Remove-Item -LiteralPath $original -Force -ErrorAction SilentlyContinue }
            }
        }
        return $manifest
    }
    catch {
        $recoverySucceeded = $false
        if (Test-Path $journal -PathType Leaf) {
            try {
                $saved = Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json
                foreach ($relative in @($saved.affected)) {
                    $target = Get-SafeChildPath $paths.Plugins ([string]$relative)
                    if (Test-Path $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
                }
                foreach ($relative in @($saved.existing)) {
                    $from = Get-SafeChildPath $rollback ([string]$relative)
                    if (Test-Path $from -PathType Leaf) {
                        $to = Get-SafeChildPath $paths.Plugins ([string]$relative)
                        $parent = Split-Path -Parent $to
                        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                        Copy-Item -LiteralPath $from -Destination $to -Force
                    }
                }
                if ([bool]$saved.hasOldManifest) {
                    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$saved.oldManifestBase64)) | Set-Content -LiteralPath $paths.Manifest -Encoding UTF8
                }
                elseif (Test-Path $paths.Manifest) { Remove-Item -LiteralPath $paths.Manifest -Force }
                $recoverySucceeded = $true
            } catch { $keepRecovery = $true }
        }
        if ($recoverySucceeded) {
            foreach ($root in @($newBackupRoots | Select-Object -Unique)) { if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } }
        }
        throw
    }
    finally {
        if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
        if (-not $keepRecovery) {
            if (Test-Path $journal) { Remove-Item -LiteralPath $journal -Force -ErrorAction SilentlyContinue }
            if (Test-Path $rollback) { Remove-Item -LiteralPath $rollback -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Set-ReShadeDllMode([string]$DllMode) {
    if (Test-FiveMRunning) { throw 'Close FiveM before changing the ReShade DLL mode.' }
    if ($DllMode -notin 'dxgi.dll','d3d11.dll') { throw 'Choose dxgi.dll or d3d11.dll.' }
    $paths = Get-ReShadePaths
    $manifest = Get-ReShadeBaseManifest
    if (-not $manifest) { throw 'Repair the ReShade install first so the app can switch DLL mode safely.' }
    $current = @($manifest.files | Where-Object { [string]$_.path -in 'dxgi.dll','d3d11.dll' } | Select-Object -First 1)
    if ($current.Count -eq 0) { throw 'The managed ReShade DLL entry is missing. Use Repair first.' }
    $sourceRelative = [string]$current[0].path
    if ($sourceRelative -ieq $DllMode) { return $manifest }
    $source = Get-SafeChildPath $paths.Plugins $sourceRelative
    if (-not (Test-Path $source -PathType Leaf)) { throw 'The current ReShade DLL is missing. Use Repair first.' }
    $target = Get-SafeChildPath $paths.Plugins $DllMode
    $temp = Join-Path $env:TEMP ('XnReShadeDll-' + [Guid]::NewGuid().ToString('N') + '.dll')
    $targetHadFile = Test-Path $target -PathType Leaf
    $transactionId = [Guid]::NewGuid().ToString('N')
    $rollback = Join-Path $paths.AppDir ".xn-reshade-manager-rollback-$transactionId"
    $journal = Join-Path $paths.AppDir '.xn-reshade-base-journal.json'
    $oldManifestRaw = Get-Content -LiteralPath $paths.Manifest -Raw
    $targetBackup = ''
    $keepRecovery = $false
    try {
        Copy-Item -LiteralPath $source -Destination $temp -Force
        New-Item -ItemType Directory -Path $rollback -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination (Get-SafeChildPath $rollback $sourceRelative) -Force
        $existing = @($sourceRelative)
        if ($targetHadFile) {
            Copy-Item -LiteralPath $target -Destination (Get-SafeChildPath $rollback $DllMode) -Force
            $existing += $DllMode
        }
        [ordered]@{
            version = 1; rollbackFolder = Split-Path $rollback -Leaf
            affected = @($sourceRelative,$DllMode); existing = @($existing)
            hasOldManifest = $true
            oldManifestBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($oldManifestRaw))
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journal -Encoding UTF8
        if ($targetHadFile) {
            $targetBackup = "$transactionId\$DllMode"
            $original = Get-SafeChildPath $paths.Backup $targetBackup
            $parent = Split-Path -Parent $original
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $target -Destination $original -Force
        }
        Remove-Item -LiteralPath $source -Force
        if ($current[0].backup) {
            $oldOriginal = Get-SafeChildPath $paths.Backup ([string]$current[0].backup)
            if (Test-Path $oldOriginal -PathType Leaf) { Copy-Item -LiteralPath $oldOriginal -Destination $source -Force }
        }
        Copy-Item -LiteralPath $temp -Destination $target -Force
        $targetItem = Get-Item -LiteralPath $target
        $remaining = @($manifest.files | Where-Object { [string]$_.path -notin 'dxgi.dll','d3d11.dll' })
        $remaining += [ordered]@{
            path = $DllMode; length = [int64]$targetItem.Length
            lastWriteUtcTicks = [int64]$targetItem.LastWriteTimeUtc.Ticks
            sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            source = 'ReShade'; backup = $targetBackup
        }
        $manifest.files = @($remaining)
        $manifest.dllMode = $DllMode
        $manifest.installedAt = [DateTime]::UtcNow.ToString('o')
        Save-ReShadeBaseManifest $manifest
        Remove-Item -LiteralPath $journal -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $rollback -Recurse -Force -ErrorAction SilentlyContinue
        if ($current[0].backup) {
            $oldOriginal = Get-SafeChildPath $paths.Backup ([string]$current[0].backup)
            if (Test-Path $oldOriginal) { Remove-Item -LiteralPath $oldOriginal -Force -ErrorAction SilentlyContinue }
        }
        return $manifest
    }
    catch {
        if (Test-Path $journal -PathType Leaf) {
            try {
                foreach ($relative in @($sourceRelative,$DllMode)) {
                    $currentFile = Get-SafeChildPath $paths.Plugins $relative
                    if (Test-Path $currentFile -PathType Leaf) { Remove-Item -LiteralPath $currentFile -Force -ErrorAction SilentlyContinue }
                }
                foreach ($relative in $existing) {
                    $from = Get-SafeChildPath $rollback $relative
                    if (Test-Path $from -PathType Leaf) { Copy-Item -LiteralPath $from -Destination (Get-SafeChildPath $paths.Plugins $relative) -Force }
                }
                $oldManifestRaw | Set-Content -LiteralPath $paths.Manifest -Encoding UTF8
                Remove-Item -LiteralPath $journal -Force -ErrorAction SilentlyContinue
                $newBackupRoot = Join-Path $paths.Backup $transactionId
                if (Test-Path $newBackupRoot) { Remove-Item -LiteralPath $newBackupRoot -Recurse -Force -ErrorAction SilentlyContinue }
            }
            catch { $keepRecovery = $true }
        }
        throw
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        if (-not $keepRecovery) {
            if (Test-Path $journal) { Remove-Item -LiteralPath $journal -Force -ErrorAction SilentlyContinue }
            if (Test-Path $rollback) { Remove-Item -LiteralPath $rollback -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Uninstall-ReShadeManaged {
    if (Test-FiveMRunning) { throw 'Close FiveM before uninstalling ReShade.' }
    $paths = Get-ReShadePaths
    $manifest = Get-ReShadeBaseManifest
    if (-not $manifest) { throw 'No managed ReShade installation was found. Nothing was removed.' }
    $rollback = Join-Path $paths.AppDir ('.xn-reshade-manager-rollback-' + [Guid]::NewGuid().ToString('N'))
    $journal = Join-Path $paths.AppDir '.xn-reshade-base-journal.json'
    $oldManifestRaw = Get-Content -LiteralPath $paths.Manifest -Raw
    $keepRecovery = $false
    try {
        New-Item -ItemType Directory -Path $rollback -Force | Out-Null
        $existing = @()
        foreach ($entry in @($manifest.files)) {
            $target = Get-SafeChildPath $paths.Plugins ([string]$entry.path)
            if (Test-Path $target -PathType Leaf) {
                $copy = Get-SafeChildPath $rollback ([string]$entry.path)
                $parent = Split-Path -Parent $copy
                if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $target -Destination $copy -Force
                $existing += [string]$entry.path
            }
        }
        [ordered]@{
            version = 1; rollbackFolder = Split-Path $rollback -Leaf
            affected = @($manifest.files | ForEach-Object { [string]$_.path }); existing = @($existing)
            hasOldManifest = $true
            oldManifestBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($oldManifestRaw))
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $journal -Encoding UTF8
        foreach ($entry in @($manifest.files)) {
            $target = Get-SafeChildPath $paths.Plugins ([string]$entry.path)
            if (Test-Path $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
            if ($entry.backup) {
                $original = Get-SafeChildPath $paths.Backup ([string]$entry.backup)
                if (Test-Path $original -PathType Leaf) {
                    $parent = Split-Path -Parent $target
                    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    Copy-Item -LiteralPath $original -Destination $target -Force
                }
            }
        }
        Remove-Item -LiteralPath $paths.Manifest -Force
        Remove-Item -LiteralPath $journal -Force -ErrorAction SilentlyContinue
        foreach ($entry in @($manifest.files)) {
            if ($entry.backup) {
                $original = Get-SafeChildPath $paths.Backup ([string]$entry.backup)
                if (Test-Path $original) { Remove-Item -LiteralPath $original -Force -ErrorAction SilentlyContinue }
            }
        }
        return @($manifest.files).Count
    }
    catch {
        try {
            foreach ($entry in @($manifest.files)) {
                $target = Get-SafeChildPath $paths.Plugins ([string]$entry.path)
                if (Test-Path $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
                $copy = Get-SafeChildPath $rollback ([string]$entry.path)
                if (Test-Path $copy -PathType Leaf) {
                    $parent = Split-Path -Parent $target
                    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    Copy-Item -LiteralPath $copy -Destination $target -Force
                }
            }
            $oldManifestRaw | Set-Content -LiteralPath $paths.Manifest -Encoding UTF8
            Remove-Item -LiteralPath $journal -Force -ErrorAction SilentlyContinue
        }
        catch { $keepRecovery = $true }
        throw
    }
    finally { if (-not $keepRecovery -and (Test-Path $rollback)) { Remove-Item -LiteralPath $rollback -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Apply-ReShadeProfile([string]$ProfileName) {
    if (-not $ProfileName -or $ProfileName -eq 'Keep current') { return }
    $clearProfile = ($ProfileName -eq '__none__')
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    if (-not (Test-Path $appDir)) { throw "FiveM isn't installed yet - run 'PC setup' first." }
    $plugins = Join-Path $appDir 'plugins'
    New-Item -ItemType Directory -Path $plugins -Force | Out-Null

    $marker = Join-Path $plugins '.xn-reshade'
    $manifestPath = Join-Path $plugins '.xn-reshade-files.json'
    $current = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { $null }
    if ($current -eq $ProfileName) { return }

    $source = $null
    if (-not $clearProfile) {
        if (-not (Test-LibraryName $ProfileName)) { throw 'The selected ReShade name is unsafe.' }
        $source = Get-SafeChildPath $script:ReshadeLibDir $ProfileName
        if (-not (Test-Path $source -PathType Container)) { throw "ReShade look '$ProfileName' is missing from the library." }
    }

    $excluded = @('dxgi.dll','d3d11.dll','.xn-reshade','.xn-reshade-files.json','.xn-reshade-base.json')
    $id = [Guid]::NewGuid().ToString('N')
    $stage = Join-Path $appDir ".xn-reshade-stage-$id"
    $rollback = Join-Path $appDir ".xn-reshade-rollback-$id"
    $journalPath = Join-Path $appDir '.xn-reshade-journal.json'
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    New-Item -ItemType Directory -Path $rollback -Force | Out-Null

    $oldManifestRaw = if (Test-Path $manifestPath) { Get-Content $manifestPath -Raw } else { $null }
    $oldMarker = if (Test-Path $marker) { Get-Content $marker -Raw } else { $null }
    $oldFiles = @()
    if ($oldManifestRaw) {
        try { $oldFiles = @((ConvertFrom-Json $oldManifestRaw).files | ForEach-Object { [string]$_ }) }
        catch { throw 'The previous ReShade file manifest is damaged. Remove .xn-reshade-files.json from the plugins folder and try again.' }
    }
    elseif ($current) {
        # Upgrade path for profiles applied by older versions that only wrote the profile marker.
        $legacySource = Join-Path $script:ReshadeLibDir $current
        if (Test-Path $legacySource -PathType Container) {
            $oldFiles = @(Get-ChildItem $legacySource -Recurse -Force -File |
                          Where-Object { $excluded -notcontains $_.Name } |
                          ForEach-Object { Get-RelativeChildPath $legacySource $_.FullName })
        }
    }
    $protectedBaseFiles = @(Get-ReShadeBaseProtectedFiles)
    if ($protectedBaseFiles.Count -gt 0) { $oldFiles = @($oldFiles | Where-Object { $protectedBaseFiles -notcontains $_ }) }

    $newFiles = @()
    try {
        if ($source) {
            Copy-DirectoryContents $source $stage $excluded
            Assert-TreesMatch $source $stage $excluded
            foreach ($file in @(Get-ChildItem $stage -Recurse -Force -File)) {
                $relative = Get-RelativeChildPath $stage $file.FullName
                if ($protectedBaseFiles -contains $relative) { Remove-Item -LiteralPath $file.FullName -Force }
            }
            $newFiles = @(Get-ChildItem $stage -Recurse -Force -File | ForEach-Object { Get-RelativeChildPath $stage $_.FullName })
            if ($newFiles.Count -eq 0) { throw "ReShade look '$ProfileName' has no profile files." }
        }

        # Back up every managed destination that may be removed or overwritten.
        $affected = @($oldFiles + $newFiles | Select-Object -Unique)
        foreach ($relative in $affected) {
            $target = Get-SafeChildPath $plugins $relative
            if (Test-Path $target -PathType Leaf) {
                $backupTarget = Get-SafeChildPath $rollback $relative
                $parent = Split-Path -Parent $backupTarget
                if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                Copy-Item -LiteralPath $target -Destination $backupTarget -Force
            }
        }

        $utf8 = [Text.Encoding]::UTF8
        [ordered]@{
            version = 1
            rollbackFolder = Split-Path $rollback -Leaf
            oldFiles = @($oldFiles)
            newFiles = @($newFiles)
            hasOldManifest = ($null -ne $oldManifestRaw)
            oldManifestBase64 = if ($null -ne $oldManifestRaw) { [Convert]::ToBase64String($utf8.GetBytes($oldManifestRaw)) } else { '' }
            hasOldMarker = ($null -ne $oldMarker)
            oldMarkerBase64 = if ($null -ne $oldMarker) { [Convert]::ToBase64String($utf8.GetBytes($oldMarker)) } else { '' }
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $journalPath -Encoding UTF8

        foreach ($relative in $oldFiles) {
            $target = Get-SafeChildPath $plugins $relative
            if (Test-Path $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
        }

        if ($source) {
            Copy-DirectoryContents $stage $plugins
            foreach ($relative in $newFiles) {
                $from = Get-SafeChildPath $stage $relative
                $to = Get-SafeChildPath $plugins $relative
                if (-not (Test-Path $to -PathType Leaf) -or (Get-Item $from).Length -ne (Get-Item $to).Length -or
                    (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash) {
                    throw "ReShade copy verification failed for $relative"
                }
            }
        }

        if ($source) {
            $manifest = [ordered]@{
                profile = $ProfileName
                appliedAt = [DateTime]::UtcNow.ToString('o')
                files = @($newFiles)
            }
            $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestPath -Encoding UTF8
            Set-Content -Path $marker -Value $ProfileName -Encoding UTF8
        }
        else {
            if (Test-Path $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
            if (Test-Path $marker) { Remove-Item -LiteralPath $marker -Force }
        }
        if (Test-Path $journalPath) { Remove-Item -LiteralPath $journalPath -Force }

        # Remove directories left empty by the old profile, deepest first.
        $oldDirs = @($oldFiles | ForEach-Object { Split-Path -Parent $_ } | Where-Object { $_ } |
                     Select-Object -Unique | Sort-Object Length -Descending)
        foreach ($relativeDir in $oldDirs) {
            $dir = Get-SafeChildPath $plugins $relativeDir
            if (Test-Path $dir -PathType Container) {
                $children = @(Get-ChildItem $dir -Force -ErrorAction SilentlyContinue)
                if ($children.Count -eq 0) { Remove-Item -LiteralPath $dir -Force }
            }
        }
    }
    catch {
        foreach ($relative in $newFiles) {
            try {
                $target = Get-SafeChildPath $plugins $relative
                if (Test-Path $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
            } catch {}
        }
        if (Test-Path $rollback) { Copy-DirectoryContents $rollback $plugins }
        if ($null -ne $oldManifestRaw) { Set-Content -Path $manifestPath -Value $oldManifestRaw -Encoding UTF8 }
        elseif (Test-Path $manifestPath) { Remove-Item $manifestPath -Force }
        if ($null -ne $oldMarker) { Set-Content -Path $marker -Value $oldMarker -Encoding UTF8 }
        elseif (Test-Path $marker) { Remove-Item $marker -Force }
        if (Test-Path $journalPath) { Remove-Item -LiteralPath $journalPath -Force -ErrorAction SilentlyContinue }
        throw
    }
    finally {
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $rollback) { Remove-Item $rollback -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Repair-InterruptedSwitches {
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    if (-not (Test-Path $appDir -PathType Container)) { return '' }
    $notes = @()
    $mods = Join-Path $appDir 'mods'

    $soundRollbacks = @(Get-ChildItem $appDir -Directory -Filter '.xn-mods-rollback-*' -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '^\.xn-mods-rollback-[a-f0-9]{32}$' } | Sort-Object LastWriteTimeUtc -Descending)
    if ($soundRollbacks.Count -gt 0 -and -not (Test-Path $mods)) {
        Move-Item -LiteralPath $soundRollbacks[0].FullName -Destination $mods -Force
        $notes += 'restored the previous soundpack after an interrupted swap'
        $soundRollbacks = @($soundRollbacks | Select-Object -Skip 1)
    }
    foreach ($folder in $soundRollbacks) { Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($stage in @(Get-ChildItem $appDir -Directory -Filter '.xn-mods-stage-*' -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match '^\.xn-mods-stage-[a-f0-9]{32}$' })) {
        Remove-Item -LiteralPath $stage.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    $plugins = Join-Path $appDir 'plugins'
    $snapshot = Join-Path $appDir '.xn-previous-plugins'
    $pluginSwaps = @(Get-ChildItem $appDir -Directory -Filter '.xn-plugins-swap-*' -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '^\.xn-plugins-swap-[a-f0-9]{32}$' } | Sort-Object LastWriteTimeUtc -Descending)
    foreach ($swap in $pluginSwaps) {
        if (-not (Test-Path $plugins)) {
            Move-Item -LiteralPath $swap.FullName -Destination $plugins -Force
            $notes += 'restored the active ReShade folder after an interrupted rollback'
        }
        elseif (-not (Test-Path $snapshot)) {
            Move-Item -LiteralPath $swap.FullName -Destination $snapshot -Force
            $notes += 'finished preserving the newer ReShade setup after a rollback'
        }
        else { Remove-Item -LiteralPath $swap.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $snapshotStages = @(Get-ChildItem $appDir -Directory -Filter '.xn-previous-plugins-stage-*' -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '^\.xn-previous-plugins-stage-[a-f0-9]{32}$' } | Sort-Object LastWriteTimeUtc -Descending)
    foreach ($stage in $snapshotStages) {
        if (-not (Test-Path $snapshot)) { Move-Item -LiteralPath $stage.FullName -Destination $snapshot -Force }
        else { Remove-Item -LiteralPath $stage.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $baseJournalPath = Join-Path $appDir '.xn-reshade-base-journal.json'
    if (Test-Path $baseJournalPath -PathType Leaf) {
        try {
            New-Item -ItemType Directory -Path $plugins -Force | Out-Null
            $baseJournal = Get-Content -LiteralPath $baseJournalPath -Raw | ConvertFrom-Json
            if ([int]$baseJournal.version -ne 1 -or [string]$baseJournal.rollbackFolder -notmatch '^\.xn-reshade-manager-rollback-[a-f0-9]{32}$') {
                throw 'The ReShade manager recovery journal is invalid.'
            }
            $baseRollback = Get-SafeChildPath $appDir ([string]$baseJournal.rollbackFolder)
            foreach ($relative in @($baseJournal.affected)) {
                $target = Get-SafeChildPath $plugins ([string]$relative)
                if (Test-Path $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
            }
            foreach ($relative in @($baseJournal.existing)) {
                $from = Get-SafeChildPath $baseRollback ([string]$relative)
                if (Test-Path $from -PathType Leaf) {
                    $to = Get-SafeChildPath $plugins ([string]$relative)
                    $parent = Split-Path -Parent $to
                    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    Copy-Item -LiteralPath $from -Destination $to -Force
                }
            }
            $baseManifestPath = Join-Path $plugins '.xn-reshade-base.json'
            if ([bool]$baseJournal.hasOldManifest) {
                $raw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$baseJournal.oldManifestBase64))
                Set-Content -LiteralPath $baseManifestPath -Value $raw -Encoding UTF8
            }
            elseif (Test-Path $baseManifestPath) { Remove-Item -LiteralPath $baseManifestPath -Force }
            if (Test-Path $baseRollback) { Remove-Item -LiteralPath $baseRollback -Recurse -Force -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $baseJournalPath -Force
            $notes += 'restored ReShade after an interrupted manager install'
        }
        catch { $notes += "could not finish ReShade manager recovery ($($_.Exception.Message))" }
    }
    if (-not (Test-Path $baseJournalPath)) {
        foreach ($folder in @(Get-ChildItem $appDir -Directory -Filter '.xn-reshade-manager-rollback-*' -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -match '^\.xn-reshade-manager-rollback-[a-f0-9]{32}$' })) {
            Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $journalPath = Join-Path $appDir '.xn-reshade-journal.json'
    if (Test-Path $journalPath -PathType Leaf) {
        try {
            New-Item -ItemType Directory -Path $plugins -Force | Out-Null
            $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
            if ([int]$journal.version -ne 1 -or [string]$journal.rollbackFolder -notmatch '^\.xn-reshade-rollback-[a-f0-9]{32}$') {
                throw 'The ReShade recovery journal is invalid.'
            }
            $rollback = Get-SafeChildPath $appDir ([string]$journal.rollbackFolder)
            foreach ($relative in @($journal.newFiles)) {
                $target = Get-SafeChildPath $plugins ([string]$relative)
                if (Test-Path $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
            }
            if (Test-Path $rollback -PathType Container) { Copy-DirectoryContents $rollback $plugins }

            $manifestPath = Join-Path $plugins '.xn-reshade-files.json'
            $markerPath = Join-Path $plugins '.xn-reshade'
            if ([bool]$journal.hasOldManifest) {
                $raw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$journal.oldManifestBase64))
                Set-Content -LiteralPath $manifestPath -Value $raw -Encoding UTF8
            }
            elseif (Test-Path $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
            if ([bool]$journal.hasOldMarker) {
                $raw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$journal.oldMarkerBase64))
                Set-Content -LiteralPath $markerPath -Value $raw -Encoding UTF8
            }
            elseif (Test-Path $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

            if (Test-Path $rollback) { Remove-Item -LiteralPath $rollback -Recurse -Force -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $journalPath -Force
            $notes += 'rolled ReShade back after an interrupted switch'
        }
        catch { $notes += "could not finish ReShade recovery ($($_.Exception.Message))" }
    }

    foreach ($stage in @(Get-ChildItem $appDir -Directory -Filter '.xn-reshade-stage-*' -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match '^\.xn-reshade-stage-[a-f0-9]{32}$' })) {
        Remove-Item -LiteralPath $stage.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $journalPath)) {
        foreach ($rollback in @(Get-ChildItem $appDir -Directory -Filter '.xn-reshade-rollback-*' -ErrorAction SilentlyContinue |
                                Where-Object { $_.Name -match '^\.xn-reshade-rollback-[a-f0-9]{32}$' })) {
            Remove-Item -LiteralPath $rollback.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if ($notes.Count -eq 0) { return '' }
    return 'Startup recovery: ' + ($notes -join '; ') + '.'
}

function Set-FiveMCanaryChannel([switch]$RequireInstalled) {
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    if (-not (Test-Path $appDir -PathType Container)) {
        if ($RequireInstalled) { throw 'FiveM is not installed for this Windows account.' }
        return $false
    }

    $iniPath = Join-Path $appDir 'CitizenFX.ini'
    $original = if (Test-Path $iniPath -PathType Leaf) { [IO.File]::ReadAllText($iniPath) } else { '' }
    if ($original -match '(?im)^\s*UpdateChannel\s*=\s*canary\s*$') { return $false }

    if ($original -match '(?im)^\s*UpdateChannel\s*=.*$') {
        $updated = [regex]::Replace($original, '(?im)^\s*UpdateChannel\s*=.*$', 'UpdateChannel=canary')
    }
    elseif ($original -match '(?im)^\s*\[Game\]\s*$') {
        $gameHeader = New-Object Text.RegularExpressions.Regex('^\s*\[Game\]\s*$',
            ([Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Multiline))
        $updated = $gameHeader.Replace($original, "`$0`r`nUpdateChannel=canary", 1)
    }
    else {
        $separator = if ($original -and -not $original.StartsWith("`r`n")) { "`r`n" } else { '' }
        $updated = "[Game]`r`nUpdateChannel=canary`r`n$separator$original"
    }

    $backupPath = $iniPath + '.xn-before-canary'
    if ((Test-Path $iniPath -PathType Leaf) -and -not (Test-Path $backupPath)) {
        Copy-Item -LiteralPath $iniPath -Destination $backupPath -Force
    }
    $temporary = $iniPath + '.xn-new-' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, $updated, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::ReadAllText($temporary) -notmatch '(?im)^\s*UpdateChannel\s*=\s*canary\s*$') {
            throw 'The new FiveM update-channel file could not be verified.'
        }
        Move-Item -LiteralPath $temporary -Destination $iniPath -Force
    }
    finally {
        if (Test-Path $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
    return $true
}

$script:StartupRecoveryNote = Repair-InterruptedSwitches
try {
    if (Set-FiveMCanaryChannel) {
        $channelNote = 'FiveM update channel set to Latest (Unstable)'
        if ($script:StartupRecoveryNote) { $script:StartupRecoveryNote += " $channelNote." }
        else { $script:StartupRecoveryNote = "$channelNote." }
    }
}
catch {
    $channelNote = "Could not set FiveM to Latest (Unstable): $($_.Exception.Message)"
    if ($script:StartupRecoveryNote) { $script:StartupRecoveryNote += " $channelNote" }
    else { $script:StartupRecoveryNote = $channelNote }
}

function Get-CurrentSwitchState {
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    $mods = Join-Path $appDir 'mods'
    $plugins = Join-Path $appDir 'plugins'
    $soundMarker = Join-Path $mods '.xn-current'
    $reshadeMarker = Join-Path $plugins '.xn-reshade'
    $sound = if (Test-Path $soundMarker) { (Get-Content -LiteralPath $soundMarker -Raw).Trim() }
             elseif ((Get-TreeStats $mods).Files -gt 0) { '__original__' }
             else { 'None' }
    $reshade = if (Test-Path $reshadeMarker) { (Get-Content -LiteralPath $reshadeMarker -Raw).Trim() } else { '__none__' }
    return [pscustomobject]@{ soundpack = $sound; reshade = $reshade; capturedAt = [DateTime]::UtcNow.ToString('o') }
}

function Save-ReShadeRollbackSnapshot {
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    $plugins = Join-Path $appDir 'plugins'
    $snapshot = Join-Path $appDir '.xn-previous-plugins'
    $stage = Join-Path $appDir ('.xn-previous-plugins-stage-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        if (Test-Path $plugins -PathType Container) {
            Copy-DirectoryContents $plugins $stage
            Assert-TreesMatch $plugins $stage
        }
        if (Test-Path $snapshot) { Remove-Item -LiteralPath $snapshot -Recurse -Force }
        Move-Item -LiteralPath $stage -Destination $snapshot -Force
    }
    finally { if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Save-SwitchRollbackState {
    $state = Get-CurrentSwitchState
    Save-ReShadeRollbackSnapshot
    Set-Prop $state 'hasReshadeSnapshot' $true
    Write-SwitchHistory $state
}

function Swap-ReShadeRollbackSnapshot {
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    $plugins = Join-Path $appDir 'plugins'
    $snapshot = Join-Path $appDir '.xn-previous-plugins'
    if (-not (Test-Path $snapshot -PathType Container)) { throw 'The previous ReShade snapshot is missing.' }
    if (-not (Test-Path $plugins -PathType Container)) { New-Item -ItemType Directory -Path $plugins -Force | Out-Null }
    $swap = Join-Path $appDir ('.xn-plugins-swap-' + [Guid]::NewGuid().ToString('N'))
    Move-Item -LiteralPath $plugins -Destination $swap -Force
    try {
        Move-Item -LiteralPath $snapshot -Destination $plugins -Force
        Move-Item -LiteralPath $swap -Destination $snapshot -Force
    }
    catch {
        if ((Test-Path $plugins) -and -not (Test-Path $snapshot)) { Move-Item -LiteralPath $plugins -Destination $snapshot -Force -ErrorAction SilentlyContinue }
        if ((Test-Path $swap) -and -not (Test-Path $plugins)) { Move-Item -LiteralPath $swap -Destination $plugins -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Write-SwitchHistory($State) {
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    if (-not (Test-Path $appDir -PathType Container)) { return }
    [ordered]@{
        version = 2
        soundpack = [string]$State.soundpack
        reshade = [string]$State.reshade
        capturedAt = [string]$State.capturedAt
        hasReshadeSnapshot = [bool]$State.hasReshadeSnapshot
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $appDir '.xn-last-switch.json') -Encoding UTF8
}

function Restore-PreviousSetup {
    if (Test-FiveMRunning) { throw 'Close FiveM before restoring the previous setup.' }
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    $historyPath = Join-Path $appDir '.xn-last-switch.json'
    if (-not (Test-Path $historyPath -PathType Leaf)) { throw 'There is no previous soundpack/ReShade setup to restore yet.' }
    $previous = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json
    if ([int]$previous.version -notin 1,2 -or -not $previous.soundpack -or -not $previous.reshade) { throw 'The previous-setup record is damaged.' }
    $redo = Get-CurrentSwitchState
    Apply-Soundpack ([string]$previous.soundpack)
    if ([int]$previous.version -ge 2 -and [bool]$previous.hasReshadeSnapshot) {
        Swap-ReShadeRollbackSnapshot
        Set-Prop $redo 'hasReshadeSnapshot' $true
    }
    else { Apply-ReShadeProfile ([string]$previous.reshade) }
    Write-SwitchHistory $redo
    $soundText = if ([string]$previous.soundpack -eq '__original__') { 'original soundpack backup' } else { [string]$previous.soundpack }
    $reshadeText = if ([string]$previous.reshade -eq '__none__') { 'no managed ReShade look' } else { [string]$previous.reshade }
    return "Restored $soundText and $reshadeText. Press Restore previous again to switch back."
}

function Normalize-ConnectTarget([string]$Connect) {
    if (-not $Connect) { return '' }
    $c = $Connect.Trim().Trim('"').Trim("'")
    $c = $c -replace '^fivem://connect/', ''
    $c = $c.TrimEnd('/')
    if ($c -match '^(?:https?://)?(?:www\.)?cfx\.re/join/([a-zA-Z0-9]{4,12})$') { return $Matches[1] }
    return $c
}

function Get-ConnectUri([string]$Connect) {
    $c = Normalize-ConnectTarget $Connect
    if ($c -match '^[a-zA-Z0-9]{4,12}$') { $c = "cfx.re/join/$c" }
    return "fivem://connect/$c"
}

function Assert-ProfileCommand([string]$Name, [AllowEmptyString()][string]$Value) {
    $cleanName = $Name.Trim()
    if ($cleanName -notmatch '^[A-Za-z_][A-Za-z0-9_.-]{0,63}$') {
        throw "'$Name' is not a valid FiveM setting name. Use letters, numbers, underscores, dots, or dashes."
    }
    if ($null -eq $Value) { $Value = '' }
    if ($Value.Length -gt 256) { throw "The value for '$cleanName' is longer than 256 characters." }
    if ($Value -match '[\x00-\x1F\x7F]' -or $Value.Contains('"')) {
        throw "The value for '$cleanName' contains an unsupported quote or control character."
    }
    return [pscustomobject]@{ name = $cleanName; value = $Value }
}

function ConvertFrom-ProfileCommandText([AllowEmptyString()][string]$Text) {
    if (-not $Text) { return @() }
    $commands = @()
    foreach ($rawLine in [regex]::Split($Text, '\r?\n')) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($commands.Count -ge 20) { throw 'Each profile can contain up to 20 FiveM server commands.' }
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_.-]{0,63})(?:\s+(.*))?$') {
            throw "Invalid profile setting: $line"
        }
        $name = [string]$Matches[1]
        $value = if ($Matches.Count -gt 2) { ([string]$Matches[2]).Trim() } else { '' }
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        elseif ($value.Contains('"')) {
            throw "The value for '$name' has unmatched or embedded quotes. Put one pair of quotes around the full value."
        }
        $commands += Assert-ProfileCommand $name $value
    }
    return @($commands)
}

function Normalize-ProfileCommands($Commands) {
    $normalized = @()
    foreach ($entry in @($Commands)) {
        if ($null -eq $entry) { continue }
        if ($entry -is [string]) {
            $normalized += @(ConvertFrom-ProfileCommandText ([string]$entry))
        }
        else {
            $normalized += Assert-ProfileCommand ([string]$entry.name) ([string]$entry.value)
        }
        if ($normalized.Count -gt 20) { throw 'Each profile can contain up to 20 FiveM server commands.' }
    }
    return @($normalized)
}

function Get-ProfileCommands($Server) {
    if ($null -eq $Server -or $null -eq $Server.PSObject.Properties['commands']) { return @() }
    return @(Normalize-ProfileCommands $Server.commands)
}

function ConvertTo-ProfileCommandText($Commands) {
    return (@(Normalize-ProfileCommands $Commands) | ForEach-Object {
        $value = [string]$_.value
        if (-not $value -or $value -match '\s') { "$($_.name) `"$value`"" }
        else { "$($_.name) $value" }
    }) -join "`r`n"
}

$script:ProfileCommandPresets = @(
    [pscustomobject]@{ Id = 'fps_counter'; Label = 'FPS counter  |  cl_drawfps 1  |  Small counter in the top-left'; Name = 'cl_drawfps'; Value = '1'; InputKey = ''; Group = ''; IsCustom = $false },
    [pscustomobject]@{ Id = 'crosshair_off'; Label = 'Crosshair off  |  profile_reticulesize -10'; Name = 'profile_reticulesize'; Value = '-10'; InputKey = ''; Group = 'reticule'; IsCustom = $false },
    [pscustomobject]@{ Id = 'crosshair_on'; Label = 'Crosshair on  |  profile_reticulesize 0'; Name = 'profile_reticulesize'; Value = '0'; InputKey = ''; Group = 'reticule'; IsCustom = $false },
    [pscustomobject]@{ Id = 'gamma'; Label = 'Brightness 35  |  profile_gamma 35'; Name = 'profile_gamma'; Value = '35'; InputKey = ''; Group = ''; IsCustom = $false },
    [pscustomobject]@{ Id = 'aim_accel'; Label = 'Aim acceleration off  |  profile_aimAcceleration 0'; Name = 'profile_aimAcceleration'; Value = '0'; InputKey = ''; Group = ''; IsCustom = $false },
    [pscustomobject]@{ Id = 'mouse_accel'; Label = 'Mouse acceleration off  |  profile_mouseAcceleration 0'; Name = 'profile_mouseAcceleration'; Value = '0'; InputKey = ''; Group = ''; IsCustom = $false },
    [pscustomobject]@{ Id = 'mouse_foot_zero'; Label = 'On-foot mouse scale 0  |  profile_mouseOnFootScale 0'; Name = 'profile_mouseOnFootScale'; Value = '0'; InputKey = ''; Group = ''; IsCustom = $false },
    [pscustomobject]@{ Id = 'mouse_accel_lower'; Label = 'Mouse acceleration off (lowercase)  |  profile_mouseacceleration 0'; Name = 'profile_mouseacceleration'; Value = '0'; InputKey = ''; Group = ''; IsCustom = $false },
    [pscustomobject]@{ Id = 'mouse_foot_custom'; Label = 'Custom on-foot mouse scale  |  profile_mouseonfootscale [value]'; Name = 'profile_mouseonfootscale'; Value = ''; InputKey = 'MouseScale'; Group = ''; IsCustom = $false },
    [pscustomobject]@{ Id = 'first_person_fov'; Label = 'First-person field of view  |  profile_fpsFieldOfView [value]'; Name = 'profile_fpsFieldOfView'; Value = ''; InputKey = 'Fov'; Group = ''; IsCustom = $false },
    [pscustomobject]@{ Id = 'sync_audio'; Label = 'Synchronous audio  |  game_useSynchronousAudio true'; Name = 'game_useSynchronousAudio'; Value = 'true'; InputKey = ''; Group = ''; IsCustom = $false },
    [pscustomobject]@{ Id = 'download_backoff'; Label = 'Faster server downloads  |  cl_rcdFailureBackoff 0'; Name = 'cl_rcdFailureBackoff'; Value = '0'; InputKey = ''; Group = ''; IsCustom = $false }
)

function Test-ProfileNumericValue([string]$Value, [string]$Label) {
    $clean = $Value.Trim()
    if ($clean -notmatch '^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$') { throw "Enter a number for $Label." }
    if ($clean.Length -gt 16) { throw "The value for $Label is too long." }
    return $clean
}

function Initialize-ProfileCommandPicker($ListBox, $Commands, $MouseScaleBox, $FovBox) {
    $ListBox.Items.Clear()
    foreach ($preset in $script:ProfileCommandPresets) { [void]$ListBox.Items.Add($preset) }

    foreach ($command in @(Normalize-ProfileCommands $Commands)) {
        $match = @($script:ProfileCommandPresets | Where-Object {
            [string]$_.Name -ceq [string]$command.name -and
            ($_.InputKey -or [string]$_.Value -ceq [string]$command.value)
        } | Select-Object -First 1)
        if ($match.Count -gt 0) {
            $preset = $match[0]
            if ([string]$preset.InputKey -eq 'MouseScale') { $MouseScaleBox.Text = [string]$command.value }
            elseif ([string]$preset.InputKey -eq 'Fov') { $FovBox.Text = [string]$command.value }
        }
        else {
            $preset = [pscustomobject]@{
                Id = 'custom_' + [Guid]::NewGuid().ToString('N')
                Label = "Custom  |  $($command.name) $($command.value)"
                Name = [string]$command.name
                Value = [string]$command.value
                InputKey = ''
                Group = ''
                IsCustom = $true
            }
            [void]$ListBox.Items.Add($preset)
        }
        [void]$ListBox.SelectedItems.Add($preset)
    }
}

function Update-ProfileCommandPicker($ListBox, $MousePanel, $FovPanel, $Summary, $EventArgs = $null) {
    if ($script:CommandSelectionGuard) { return }
    $script:CommandSelectionGuard = $true
    try {
        if ($EventArgs -and $EventArgs.AddedItems) {
            foreach ($added in @($EventArgs.AddedItems)) {
                $group = [string]$added.Group
                if (-not $group) { continue }
                foreach ($selected in @($ListBox.SelectedItems)) {
                    if ($selected -ne $added -and [string]$selected.Group -eq $group) {
                        [void]$ListBox.SelectedItems.Remove($selected)
                    }
                }
            }
        }
        $inputKeys = @($ListBox.SelectedItems | ForEach-Object { [string]$_.InputKey })
        $MousePanel.Visibility = if ($inputKeys -contains 'MouseScale') { 'Visible' } else { 'Collapsed' }
        $FovPanel.Visibility = if ($inputKeys -contains 'Fov') { 'Visible' } else { 'Collapsed' }
        if ($Summary) {
            $count = $ListBox.SelectedItems.Count
            $Summary.Text = if ($count -eq 0) { 'Click one command. Hold Ctrl while clicking to choose several.' }
                            elseif ($count -eq 1) { '1 command selected. Hold Ctrl while clicking to add more.' }
                            else { "$count commands selected. Ctrl+click a command to remove it." }
        }
    }
    finally { $script:CommandSelectionGuard = $false }
}

function Get-ProfileCommandsFromPicker($ListBox, $MouseScaleBox, $FovBox) {
    $commands = @()
    $groups = @{}
    foreach ($item in @($ListBox.Items)) {
        if (-not $ListBox.SelectedItems.Contains($item)) { continue }
        $group = [string]$item.Group
        if ($group) {
            if ($groups.ContainsKey($group)) { throw 'Choose either Crosshair off or Crosshair on, not both.' }
            $groups[$group] = $true
        }
        $value = switch ([string]$item.InputKey) {
            'MouseScale' { Test-ProfileNumericValue $MouseScaleBox.Text 'custom on-foot mouse scale' }
            'Fov' { Test-ProfileNumericValue $FovBox.Text 'first-person field of view' }
            default { [string]$item.Value }
        }
        $commands += Assert-ProfileCommand ([string]$item.Name) $value
    }
    if ($commands.Count -gt 20) { throw 'Each profile can contain up to 20 FiveM server commands.' }
    return @($commands)
}

function Add-CustomProfileCommandToPicker($ListBox, $NameBox, $ValueBox) {
    $command = Assert-ProfileCommand $NameBox.Text $ValueBox.Text
    $existingPreset = @($script:ProfileCommandPresets | Where-Object {
        [string]$_.Name -ceq [string]$command.name -and
        -not $_.InputKey -and [string]$_.Value -ceq [string]$command.value
    } | Select-Object -First 1)

    foreach ($item in @($ListBox.Items)) {
        if ([string]$item.Name -cne [string]$command.name) { continue }
        [void]$ListBox.SelectedItems.Remove($item)
        if ([bool]$item.IsCustom) { [void]$ListBox.Items.Remove($item) }
    }

    if ($existingPreset.Count -gt 0) {
        $item = $existingPreset[0]
        [void]$ListBox.SelectedItems.Add($item)
    }
    else {
        $item = [pscustomobject]@{
            Id = 'custom_' + [Guid]::NewGuid().ToString('N')
            Label = "Custom  |  $($command.name) $($command.value)"
            Name = [string]$command.name
            Value = [string]$command.value
            InputKey = ''
            Group = ''
            IsCustom = $true
        }
        [void]$ListBox.Items.Add($item)
        [void]$ListBox.SelectedItems.Add($item)
    }
    $NameBox.Text = ''
    $ValueBox.Text = ''
    return $item
}

function Remove-SelectedCustomProfileCommands($ListBox) {
    $selected = @($ListBox.SelectedItems | Where-Object { [bool]$_.IsCustom })
    foreach ($item in $selected) { [void]$ListBox.Items.Remove($item) }
    return $selected.Count
}

function ConvertTo-WindowsArgument([AllowEmptyString()][string]$Value) {
    if ($null -eq $Value) { $Value = '' }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append((('\' * (($slashes * 2) + 1)) -join ''))
            [void]$builder.Append('"')
        }
        else {
            if ($slashes -gt 0) { [void]$builder.Append((('\' * $slashes) -join '')) }
            [void]$builder.Append($character)
        }
        $slashes = 0
    }
    if ($slashes -gt 0) { [void]$builder.Append((('\' * ($slashes * 2)) -join '')) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-FiveMExecutable {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.exe'),
        (Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app\FiveM.exe')
    )
    foreach ($registryPath in 'HKCU:\Software\Classes\fivem\shell\open\command','Registry::HKEY_CLASSES_ROOT\fivem\shell\open\command') {
        try {
            $command = [Environment]::ExpandEnvironmentVariables([string](Get-Item -LiteralPath $registryPath -ErrorAction Stop).GetValue(''))
            if ($command -match '^\s*"([^"]+FiveM\.exe)"' -or $command -match '^\s*([^\s]+FiveM\.exe)') { $candidates += [string]$Matches[1] }
        }
        catch {}
    }
    foreach ($candidate in @($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    return $null
}

function Get-FiveMLaunchArguments([string]$Connect, $Commands) {
    $parts = @()
    foreach ($command in @(Normalize-ProfileCommands $Commands)) {
        $parts += '+set'
        $parts += ConvertTo-WindowsArgument ([string]$command.name)
        $parts += ConvertTo-WindowsArgument ([string]$command.value)
    }
    $target = Normalize-ConnectTarget $Connect
    if ($target -match '^[a-zA-Z0-9]{4,12}$') { $target = "cfx.re/join/$target" }
    $parts += '+connect'
    $parts += ConvertTo-WindowsArgument $target
    return $parts -join ' '
}

function Test-FiveMConnectTarget([string]$Connect) {
    $target = Normalize-ConnectTarget $Connect
    if (-not $target) { return [pscustomobject]@{ Online = $false; Connect = ''; Name = ''; Players = ''; Detail = 'Enter a connect code or IP first.' } }

    if ($target -match '^[a-zA-Z0-9]{4,12}$') {
        try {
            $uri = "https://servers-frontend.fivem.net/api/servers/single/$target"
            $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 7 -UseBasicParsing -ErrorAction Stop
            $data = $response.Data
            if (-not $data) { throw 'The server was not returned by the Cfx listing service.' }
            $name = if ($data.vars -and $data.vars.sv_projectName) { [string]$data.vars.sv_projectName }
                    elseif ($data.hostname) { [string]$data.hostname } else { '' }
            $players = if ($null -ne $data.clients -and $null -ne $data.svMaxclients) {
                "$($data.clients)/$($data.svMaxclients) players"
            } else { '' }
            return [pscustomobject]@{ Online = $true; Connect = $target; Name = $name; Players = $players; Detail = 'Connect code verified by Cfx.re.' }
        }
        catch {
            return [pscustomobject]@{ Online = $false; Connect = $target; Name = ''; Players = ''; Detail = "Connect code could not be verified: $($_.Exception.Message)" }
        }
    }

    $endpoint = $target
    if ($endpoint -notmatch ':\d+$' -and $endpoint -notmatch '/') { $endpoint = "$endpoint`:30120" }
    $baseUri = if ($endpoint -match '^https?://') { $endpoint.TrimEnd('/') } else { "http://$($endpoint.TrimEnd('/'))" }
    try {
        $info = Invoke-RestMethod -Uri "$baseUri/info.json" -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if (-not ($info.vars -or $info.resources -or $info.server)) { throw 'The endpoint did not return FiveM server metadata.' }
        $name = if ($info.vars -and $info.vars.sv_projectName) { [string]$info.vars.sv_projectName }
                elseif ($info.vars -and $info.vars.sv_hostname) { [string]$info.vars.sv_hostname } else { '' }
        $players = ''
        try {
            $dynamic = Invoke-RestMethod -Uri "$baseUri/dynamic.json" -Method Get -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            if ($null -ne $dynamic.clients -and $null -ne $dynamic.sv_maxclients) {
                $players = "$($dynamic.clients)/$($dynamic.sv_maxclients) players"
            }
        } catch {}
        return [pscustomobject]@{ Online = $true; Connect = $target; Name = $name; Players = $players; Detail = 'FiveM info.json responded.' }
    }
    catch {
        return [pscustomobject]@{ Online = $false; Connect = $target; Name = ''; Players = ''; Detail = "Endpoint is offline or hidden behind a proxy: $($_.Exception.Message)" }
    }
}

function Get-FiveMServerHint {
    $logCode = $null
    $logEndpoint = $null
    $logDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app\logs'

    # Recent client logs often retain either the cfx.re join link or resolved endpoint.
    if (Test-Path $logDir) {
        $logs = @(Get-ChildItem $logDir -Filter 'CitizenFX_log_*.log' -File -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 3)
        foreach ($log in $logs) {
            $lines = @(Get-Content $log.FullName -Tail 1200 -ErrorAction SilentlyContinue)
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $line = [string]$lines[$i]
                if (-not $logCode -and $line -match '(?i)cfx\.re/join/([a-z0-9]{4,12})') {
                    $logCode = [string]$Matches[1]
                }
                if (-not $logEndpoint -and
                    $line -match '(?i)(?:connect(?:ing|ed)?(?:\s+to)?|server\s+endpoint|resolved\s+endpoint).*?((?:\d{1,3}\.){3}\d{1,3}:\d{2,5})') {
                    $logEndpoint = [string]$Matches[1]
                }
                if ($logCode -and $logEndpoint) { break }
            }
            if ($logCode -or $logEndpoint) { break }
        }
    }

    if ($logCode) {
        return [pscustomobject]@{ Connect = $logCode; Name = ''; Source = 'recent FiveM connect code' }
    }

    # While FiveM is connected, verify its TCP peers against the standard server info endpoint.
    $fiveMProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'FiveM*' })
    if ($fiveMProcesses.Count -gt 0 -and (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        $ids = @($fiveMProcesses | ForEach-Object Id)
        $seen = @{}
        $connections = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
                         Where-Object {
                             $ids -contains $_.OwningProcess -and
                             $_.RemoteAddress -match '^(?:\d{1,3}\.){3}\d{1,3}$' -and
                             $_.RemoteAddress -notmatch '^(?:0\.|127\.|169\.254\.)'
                         } |
                         Sort-Object @{ Expression = {
                             if ($_.RemotePort -eq 30120) { 0 }
                             elseif ($_.RemotePort -notin 80, 443) { 1 }
                             else { 2 }
                         } })

        foreach ($conn in $connections) {
            $key = "$($conn.RemoteAddress):$($conn.RemotePort)"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $schemes = if ($conn.RemotePort -eq 443) { @('https') } else { @('http') }
            foreach ($scheme in $schemes) {
                $uri = "${scheme}://$($conn.RemoteAddress):$($conn.RemotePort)/info.json"
                try {
                    $info = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
                    if ($info.vars -or $info.resources -or $info.server) {
                        $serverName = ''
                        if ($info.vars -and $info.vars.sv_projectName) { $serverName = [string]$info.vars.sv_projectName }
                        elseif ($info.vars -and $info.vars.sv_hostname) { $serverName = [string]$info.vars.sv_hostname }
                        return [pscustomobject]@{ Connect = $key; Name = $serverName; Source = 'active FiveM connection' }
                    }
                } catch {}
            }
        }
    }

    if ($logEndpoint) {
        return [pscustomobject]@{ Connect = $logEndpoint; Name = ''; Source = 'recent FiveM endpoint' }
    }
    return $null
}

function Invoke-PlayServer($Srv, [scriptblock]$Status) {
    $say = { param($m) if ($Status) { & $Status $m } }
    try {
        $profileCommands = @(Get-ProfileCommands $Srv)
        [void](Set-FiveMCanaryChannel -RequireInstalled)
    }
    catch {
        [Windows.MessageBox]::Show("Couldn't prepare FiveM for $($Srv.name):`n`n$($_.Exception.Message)", 'Xn Fresh Deploy') | Out-Null
        & $say 'FiveM is not ready.'
        return $false
    }
    if (Test-FiveMRunning) {
        if ($profileCommands.Count -gt 0) {
            [Windows.MessageBox]::Show(
                "Close FiveM before launching $($Srv.name).`n`nThis profile has $($profileCommands.Count) server command(s). Starting a fresh FiveM session is how Fresh Deploy keeps them tied to this profile.",
                'Xn Fresh Deploy', 'OK', 'Information') | Out-Null
            & $say 'Close FiveM, then press Play again.'
            return $false
        }
        $r = [Windows.MessageBox]::Show(
            "FiveM is already open, so your soundpack and ReShade can't be switched right now.`n`nConnect to $($Srv.name) anyway with whatever's currently applied?",
            'Xn Fresh Deploy', 'YesNo', 'Question')
        if ($r -ne 'Yes') { & $say 'Cancelled.'; return $false }
    }
    else {
        try {
            Save-SwitchRollbackState
            & $say "Soundpack: $($Srv.soundpack)..."
            Apply-Soundpack ([string]$Srv.soundpack)
            & $say "ReShade: $($Srv.reshade)..."
            Apply-ReShadeProfile ([string]$Srv.reshade)
            if ($profileCommands.Count -gt 0) { & $say "Server commands: $($profileCommands.Count)..." }
        }
        catch {
            [Windows.MessageBox]::Show("Couldn't get things ready for $($Srv.name):`n`n$($_.Exception.Message)", 'Xn Fresh Deploy') | Out-Null
            & $say 'Something went wrong.'
            return $false
        }
    }
    & $say "Connecting to $($Srv.name)..."
    try {
        if ($profileCommands.Count -gt 0) {
            $fiveMExe = Get-FiveMExecutable
            if (-not $fiveMExe) { throw 'FiveM.exe could not be found. Open FiveM once, then try this profile again.' }
            $arguments = Get-FiveMLaunchArguments ([string]$Srv.connect) $profileCommands
            Start-Process -FilePath $fiveMExe -ArgumentList $arguments
        }
        else { Start-Process (Get-ConnectUri ([string]$Srv.connect)) }
        Set-Prop $Srv 'lastPlayed' ([DateTime]::UtcNow.ToString('o'))
        Save-Servers
    }
    catch {
        [Windows.MessageBox]::Show("Couldn't open FiveM: $($_.Exception.Message)", 'Xn Fresh Deploy') | Out-Null
        return $false
    }
    return $true
}

function Get-ServerShortcutPath([string]$Name) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $safe = ($Name -replace '[\\/:*?"<>|]', '_')
    return Join-Path $desktop "$safe.lnk"
}

function New-ServerShortcut($Srv) {
    $lnkPath = Get-ServerShortcutPath ([string]$Srv.name)
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath = 'powershell.exe'
    $lnk.Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Play `"$($Srv.name)`""
    $lnk.WorkingDirectory = $script:ScriptDir
    $ico = Join-Path $script:ScriptDir 'icon.ico'
    if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" }
    $lnk.Description = "Play $($Srv.name) with your saved soundpack and ReShade"
    $lnk.Save()
    return $lnkPath
}

function Update-ServerShortcut([string]$OldName, $Srv) {
    $oldPath = Get-ServerShortcutPath $OldName
    if (-not (Test-Path $oldPath -PathType Leaf)) { return $false }
    $newPath = New-ServerShortcut $Srv
    if ($oldPath -ine $newPath -and (Test-Path $oldPath)) { Remove-Item -LiteralPath $oldPath -Force }
    return $true
}

function Remove-ServerShortcut([string]$Name) {
    $path = Get-ServerShortcutPath $Name
    if (Test-Path $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force; return $true }
    return $false
}

# ==============================================================================
#  -Play mode: tiny splash, apply packs, connect, done. No admin needed.
# ==============================================================================
if ($Play) {
    $srv = $script:Servers | Where-Object { [string]$_.name -eq $Play } | Select-Object -First 1
    if (-not $srv) {
        [Windows.MessageBox]::Show("No server called '$Play' is saved in the app. Open Xn Fresh Deploy and check the Play tab.", 'Xn Fresh Deploy') | Out-Null
        exit 1
    }

    $splash = New-Object System.Windows.Window
    $splash.WindowStyle = 'None'
    $splash.AllowsTransparency = $true
    $splash.Background = [System.Windows.Media.Brushes]::Transparent
    $splash.SizeToContent = 'WidthAndHeight'
    $splash.WindowStartupLocation = 'CenterScreen'
    $splash.Topmost = $true
    $splash.ShowInTaskbar = $false

    $card = New-Object System.Windows.Controls.Border
    $card.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#161B22'))
    $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#262D38'))
    $card.BorderThickness = New-Object System.Windows.Thickness(1)
    $card.CornerRadius = New-Object System.Windows.CornerRadius(14)
    $card.Padding = New-Object System.Windows.Thickness(24, 18, 28, 18)

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'

    $tile = New-Object System.Windows.Controls.Border
    $grad = New-Object System.Windows.Media.LinearGradientBrush
    $grad.StartPoint = New-Object System.Windows.Point(0, 0)
    $grad.EndPoint   = New-Object System.Windows.Point(1, 1)
    [void]$grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#7C6CFF'), 0)))
    [void]$grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.ColorConverter]::ConvertFromString('#4ED0FF'), 1)))
    $tile.Background = $grad
    $tile.Width = 40; $tile.Height = 40
    $tile.CornerRadius = New-Object System.Windows.CornerRadius(11)
    $tileText = New-Object System.Windows.Controls.TextBlock
    $tileText.Text = 'XN'; $tileText.FontSize = 16; $tileText.FontWeight = 'Bold'
    $tileText.Foreground = [System.Windows.Media.Brushes]::White
    $tileText.HorizontalAlignment = 'Center'; $tileText.VerticalAlignment = 'Center'
    $tile.Child = $tileText
    [void]$row.Children.Add($tile)

    $col = New-Object System.Windows.Controls.StackPanel
    $col.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
    $col.VerticalAlignment = 'Center'
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Loading $($srv.name)"
    $title.FontSize = 15; $title.FontWeight = 'SemiBold'
    $title.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
    $title.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#E6EDF3'))
    [void]$col.Children.Add($title)
    $status = New-Object System.Windows.Controls.TextBlock
    $status.Text = 'Getting things ready...'
    $status.FontSize = 12
    $status.FontFamily = $title.FontFamily
    $status.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#8B949E'))
    $status.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
    [void]$col.Children.Add($status)
    [void]$row.Children.Add($col)

    $card.Child = $row
    $splash.Content = $card
    $splash.Show()

    function Pump-Ui { $splash.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
    Pump-Ui

    $ok = Invoke-PlayServer $srv { param($m) $status.Text = $m; Pump-Ui }
    if ($ok) {
        $status.Text = 'FiveM is taking over - have fun.'
        Pump-Ui
        Start-Sleep -Milliseconds 1600
    }
    $splash.Close()
    exit 0
}

# ==============================================================================
#  Main app UI
# ==============================================================================
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Xn Fresh Deploy" Height="840" Width="1180" MinHeight="720" MinWidth="1020"
        WindowStartupLocation="CenterScreen" Background="#0B0F17"
        FontFamily="Segoe UI" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="CardBrush"   Color="#161B22"/>
    <SolidColorBrush x:Key="EdgeBrush"   Color="#262D38"/>
    <SolidColorBrush x:Key="InkBrush"    Color="#E6EDF3"/>
    <SolidColorBrush x:Key="MutedBrush"  Color="#8B949E"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#7C6CFF"/>
    <LinearGradientBrush x:Key="AccentGrad" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#7C6CFF" Offset="0"/>
      <GradientStop Color="#4ED0FF" Offset="1"/>
    </LinearGradientBrush>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource InkBrush}"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource CardBrush}"/>
      <Setter Property="BorderBrush" Value="{StaticResource EdgeBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="16"/>
    </Style>
    <Style x:Key="SectionTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{StaticResource InkBrush}"/>
    </Style>
    <Style x:Key="Eyebrow" TargetType="TextBlock">
      <Setter Property="FontSize" Value="10.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#8FA4FF"/>
    </Style>
    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Foreground" Value="{StaticResource MutedBrush}"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="0,4,0,0"/>
    </Style>
    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource MutedBrush}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="Transparent" BorderBrush="{StaticResource EdgeBrush}"
                    BorderThickness="1" CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1F2630"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="26,12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="10"
                    Padding="{TemplateBinding Padding}">
              <Border.Effect>
                <DropShadowEffect BlurRadius="20" ShadowDepth="0" Color="#7C6CFF" Opacity="0.35"/>
              </Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#8F7FFF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#3A3F4B"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimarySm" TargetType="Button">
      <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Padding" Value="18,7"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#8F7FFF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#3A3F4B"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="NavOff" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource MutedBrush}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="16,7"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="Transparent" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1A202A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="NavOn" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="16,7"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="#232B3A" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Width="44" Height="24" Background="Transparent">
              <Border x:Name="track" CornerRadius="12" Background="#2A3140"/>
              <Ellipse x:Name="thumb" Width="18" Height="18" Fill="#8B949E"
                       HorizontalAlignment="Left" Margin="3,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="{StaticResource AccentBrush}"/>
                <Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="thumb" Property="Margin" Value="0,0,3,0"/>
                <Setter TargetName="thumb" Property="Fill" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{StaticResource InkBrush}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="9,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="bd" Background="Transparent" Padding="{TemplateBinding Padding}" CornerRadius="6" Margin="3,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#242C3A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DarkCombo" TargetType="ComboBox">
      <Setter Property="Foreground" Value="{StaticResource InkBrush}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="MinWidth" Value="140"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="bd" Background="#1B2230" BorderBrush="#262D38" BorderThickness="1" CornerRadius="7">
                      <TextBlock Text="&#x25BE;" FontSize="10" Foreground="#8B949E"
                                 HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,9,0"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="bd" Property="Background" Value="#212939"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                TextElement.Foreground="{TemplateBinding Foreground}"
                                Margin="10,0,26,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True"
                     PopupAnimation="Fade">
                <Border Background="#1B2230" BorderBrush="#262D38" BorderThickness="1" CornerRadius="8"
                        Margin="0,4,0,4" Padding="0,3"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                        MaxHeight="230">
                  <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <ItemsPresenter/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DarkText" TargetType="TextBox">
      <Setter Property="Foreground" Value="{StaticResource InkBrush}"/>
      <Setter Property="Background" Value="#1B2230"/>
      <Setter Property="BorderBrush" Value="#262D38"/>
      <Setter Property="CaretBrush" Value="{StaticResource InkBrush}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Padding" Value="9,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="7">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DarkListItem" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="{StaticResource InkBrush}"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Padding" Value="9,7"/>
      <Setter Property="Margin" Value="3,1"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="bd" Background="Transparent" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter TextElement.Foreground="{TemplateBinding Foreground}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#242C3A"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#344569"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DarkList" TargetType="ListBox">
      <Setter Property="Foreground" Value="{StaticResource InkBrush}"/>
      <Setter Property="Background" Value="#1B2230"/>
      <Setter Property="BorderBrush" Value="#262D38"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="2"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource DarkListItem}"/>
      <Setter Property="ScrollViewer.VerticalScrollBarVisibility" Value="Auto"/>
    </Style>
  </Window.Resources>

  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <Grid Grid.Row="0" Margin="2,0,2,12">
      <StackPanel Orientation="Horizontal">
        <Border Width="42" Height="42" CornerRadius="11" Background="{StaticResource AccentGrad}">
          <Border.Effect>
            <DropShadowEffect BlurRadius="18" ShadowDepth="0" Color="#7C6CFF" Opacity="0.45"/>
          </Border.Effect>
          <TextBlock Text="XN" FontSize="17" FontWeight="Bold" Foreground="White"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
          <TextBlock Text="Fresh Deploy" FontSize="19" FontWeight="SemiBold"/>
          <TextBlock Text="One setup. A perfect FiveM profile for every server." FontSize="12"
                     Foreground="{StaticResource MutedBrush}"/>
        </StackPanel>
      </StackPanel>
        <TextBlock Text="v3.10" FontSize="11" Foreground="{StaticResource MutedBrush}"
                 HorizontalAlignment="Right" VerticalAlignment="Top"/>
    </Grid>

    <!-- Nav -->
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="2,0,0,14">
      <Button x:Name="NavPlay" Content="Server profiles" Style="{StaticResource NavOn}"/>
      <Button x:Name="NavSetup" Content="PC setup" Style="{StaticResource NavOff}" Margin="8,0,0,0"/>
    </StackPanel>

    <!-- ===================== SERVER PROFILES ===================== -->
    <Grid Grid.Row="2" x:Name="PlayScreen" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="#131A2A" BorderBrush="#283557" BorderThickness="1"
              CornerRadius="14" Padding="18,14" Margin="0,0,0,14">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel>
            <TextBlock Text="SERVER PROFILES" Style="{StaticResource Eyebrow}"/>
            <TextBlock Text="Your server, your sound, your look." FontSize="20" FontWeight="SemiBold" Margin="0,3,0,0"/>
            <TextBlock Text="Choose a soundpack and ReShade preset once. Fresh Deploy applies both before it connects."
                       Style="{StaticResource Hint}" MaxWidth="650" HorizontalAlignment="Left"/>
          </StackPanel>
          <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
            <Border Background="#1A2337" CornerRadius="9" Padding="12,8" Margin="0,0,8,0">
              <StackPanel>
                <TextBlock Text="PROFILES" Style="{StaticResource Eyebrow}"/>
                <TextBlock x:Name="TxtProfileSummary" Text="0 saved" FontSize="13" FontWeight="SemiBold" Margin="0,2,0,0"/>
              </StackPanel>
            </Border>
            <Border Background="#1A2337" CornerRadius="9" Padding="12,8">
              <StackPanel>
                <TextBlock Text="LIBRARY" Style="{StaticResource Eyebrow}"/>
                <TextBlock x:Name="TxtLibrarySummary" Text="0 packs / 0 looks" FontSize="13" FontWeight="SemiBold" Margin="0,2,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </Grid>
      </Border>

      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="14"/>
          <ColumnDefinition Width="360"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Style="{StaticResource Card}" Padding="18">
          <DockPanel>
            <DockPanel DockPanel.Dock="Top" Margin="0,0,0,12" LastChildFill="True">
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                <Button x:Name="BtnRestorePrevious" Content="Restore previous" Style="{StaticResource Ghost}" Margin="0,0,6,0"/>
                <Button x:Name="BtnImportProfiles" Content="Import" Style="{StaticResource Ghost}" Margin="0,0,6,0"/>
                <Button x:Name="BtnPortableProfiles" Content="Full backup" Style="{StaticResource Ghost}" Margin="0,0,6,0"/>
                <Button x:Name="BtnExportProfiles" Content="Export" Style="{StaticResource Ghost}"/>
              </StackPanel>
              <StackPanel>
                <TextBlock Text="Saved profiles" Style="{StaticResource SectionTitle}"/>
                <TextBlock Style="{StaticResource Hint}"
                           Text="Every change is saved automatically. Press Play to apply that profile and connect."/>
              </StackPanel>
            </DockPanel>
            <Grid DockPanel.Dock="Top" Margin="0,0,0,12">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="180"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="SEARCH" Style="{StaticResource Eyebrow}" Margin="1,0,0,5"/>
                <TextBox x:Name="TxtProfileSearch" Style="{StaticResource DarkText}" Height="34"/>
              </StackPanel>
              <StackPanel Grid.Column="2">
                <TextBlock Text="SORT" Style="{StaticResource Eyebrow}" Margin="1,0,0,5"/>
                <ComboBox x:Name="CmbProfileSort" Style="{StaticResource DarkCombo}" Height="34"/>
              </StackPanel>
            </Grid>
            <ScrollViewer VerticalScrollBarVisibility="Hidden">
              <StackPanel>
                <Border x:Name="NoServersText" Background="#111722" BorderBrush="#263149" BorderThickness="1"
                        CornerRadius="12" Padding="24" Margin="0,2,0,0">
                  <StackPanel HorizontalAlignment="Center">
                    <TextBlock x:Name="NoServersTitle" Text="No server profiles yet" FontSize="15" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                    <TextBlock x:Name="NoServersHint" Text="Create one with the configurator on the right."
                               Style="{StaticResource Hint}" HorizontalAlignment="Center"/>
                  </StackPanel>
                </Border>
                <StackPanel x:Name="ServersPanel"/>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>
        </Border>

        <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Hidden">
          <StackPanel>
            <Border Style="{StaticResource Card}" BorderBrush="#4859A6" Margin="0,0,0,12" Padding="18">
              <StackPanel>
                <TextBlock Text="CREATE A PROFILE" Style="{StaticResource Eyebrow}"/>
                <TextBlock Text="Add a server" FontSize="17" FontWeight="SemiBold" Margin="0,3,0,0"/>
                <TextBlock Text="Save the server and the exact setup you want it to use." Style="{StaticResource Hint}"/>

                <TextBlock Text="PROFILE NAME" Style="{StaticResource Eyebrow}" Margin="0,14,0,5"/>
                <TextBox x:Name="TxtNewName" Style="{StaticResource DarkText}" Height="34"/>

                <TextBlock Text="CONNECT CODE, LINK, OR IP" Style="{StaticResource Eyebrow}" Margin="0,11,0,5"/>
                <TextBox x:Name="TxtNewConnect" Style="{StaticResource DarkText}" Height="34"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,7,0,0">
                  <Button x:Name="BtnTestServer" Content="Test connection" Style="{StaticResource Ghost}"/>
                  <Button x:Name="BtnDetectServer" Content="Detect from FiveM" Style="{StaticResource Ghost}" Margin="7,0,0,0"/>
                </StackPanel>
                <TextBlock Text="Paste a code or link, or join once and let Fresh Deploy detect the server."
                           Style="{StaticResource Hint}"/>

                <Grid Margin="0,12,0,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="10"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0">
                    <TextBlock Text="SOUNDPACK" Style="{StaticResource Eyebrow}" Margin="0,0,0,5"/>
                    <ComboBox x:Name="CmbNewSound" Style="{StaticResource DarkCombo}" Height="34" HorizontalAlignment="Stretch"/>
                  </StackPanel>
                  <StackPanel Grid.Column="2">
                    <TextBlock Text="RESHADE LOOK" Style="{StaticResource Eyebrow}" Margin="0,0,0,5"/>
                    <ComboBox x:Name="CmbNewReshade" Style="{StaticResource DarkCombo}" Height="34" HorizontalAlignment="Stretch"/>
                  </StackPanel>
                </Grid>

                <TextBlock Text="SERVER COMMANDS" Style="{StaticResource Eyebrow}" Margin="0,12,0,5"/>
                <ListBox x:Name="LstNewCommands" Style="{StaticResource DarkList}" Height="190" SelectionMode="Extended">
                  <ListBox.ItemTemplate>
                    <DataTemplate><TextBlock Text="{Binding Label}" TextWrapping="Wrap"/></DataTemplate>
                  </ListBox.ItemTemplate>
                </ListBox>
                <TextBlock x:Name="TxtNewCommandSummary" Text="Click one command. Hold Ctrl while clicking to choose several."
                           Style="{StaticResource Hint}"/>
                <StackPanel x:Name="PnlNewMouseScale" Visibility="Collapsed" Margin="0,9,0,0">
                  <TextBlock Text="ON-FOOT MOUSE SCALE VALUE" Style="{StaticResource Eyebrow}" Margin="0,0,0,5"/>
                  <TextBox x:Name="TxtNewMouseScale" Style="{StaticResource DarkText}" Height="34"/>
                </StackPanel>
                <StackPanel x:Name="PnlNewFov" Visibility="Collapsed" Margin="0,9,0,0">
                  <TextBlock Text="FIRST-PERSON FOV VALUE" Style="{StaticResource Eyebrow}" Margin="0,0,0,5"/>
                  <TextBox x:Name="TxtNewFov" Style="{StaticResource DarkText}" Height="34"/>
                  <TextBlock Text="This command only works on servers that allow it." Style="{StaticResource Hint}"/>
                </StackPanel>

                <Border Background="#111722" BorderBrush="#263149" BorderThickness="1" CornerRadius="9" Padding="11" Margin="0,11,0,0">
                  <StackPanel>
                    <TextBlock Text="ADD YOUR OWN COMMAND" Style="{StaticResource Eyebrow}"/>
                    <Grid Margin="0,7,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                      <StackPanel Grid.Column="0">
                        <TextBlock Text="COMMAND NAME" Style="{StaticResource Eyebrow}" Margin="0,0,0,4"/>
                        <TextBox x:Name="TxtNewCustomName" Style="{StaticResource DarkText}" Height="34"/>
                      </StackPanel>
                      <StackPanel Grid.Column="2">
                        <TextBlock Text="VALUE" Style="{StaticResource Eyebrow}" Margin="0,0,0,4"/>
                        <TextBox x:Name="TxtNewCustomValue" Style="{StaticResource DarkText}" Height="34"/>
                      </StackPanel>
                    </Grid>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
                      <Button x:Name="BtnRemoveNewCustom" Content="Remove selected custom" Style="{StaticResource Ghost}"/>
                      <Button x:Name="BtnAddNewCustom" Content="Add command" Style="{StaticResource Ghost}" Margin="7,0,0,0"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtNewCustomStatus" Text="Enter a command name and value, then press Add command."
                               Style="{StaticResource Hint}"/>
                  </StackPanel>
                </Border>

                <Button x:Name="BtnAddServer" Content="Create server profile" Style="{StaticResource Primary}"
                        HorizontalAlignment="Stretch" Margin="0,16,0,0"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,12" Padding="18">
              <StackPanel>
                <DockPanel LastChildFill="True">
                  <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <Button x:Name="BtnManageLibraries" Content="Manage" Style="{StaticResource Ghost}" Margin="0,0,6,0"/>
                    <Button x:Name="BtnRefreshLibraries" Content="Refresh" Style="{StaticResource Ghost}"/>
                  </StackPanel>
                  <StackPanel>
                    <TextBlock Text="Pack library" Style="{StaticResource SectionTitle}"/>
                    <TextBlock Text="Folders become choices in every profile." Style="{StaticResource Hint}"/>
                  </StackPanel>
                </DockPanel>

                <Border Background="#111722" CornerRadius="10" Padding="12" Margin="0,12,0,0">
                  <StackPanel>
                    <TextBlock Text="SOUNDPACKS" Style="{StaticResource Eyebrow}"/>
                    <TextBlock x:Name="TxtSoundList" Style="{StaticResource Hint}" Margin="0,4,0,0" Foreground="{StaticResource InkBrush}"/>
                    <Button x:Name="BtnOpenSounds" Content="Open folder" Style="{StaticResource Ghost}"
                            HorizontalAlignment="Left" Margin="0,8,0,0"/>
                    <Grid Margin="0,8,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="8"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBox x:Name="TxtSoundName" Style="{StaticResource DarkText}"/>
                      <Button x:Name="BtnSaveSound" Grid.Column="2" Content="Capture current" Style="{StaticResource Ghost}" Height="30"/>
                    </Grid>
                  </StackPanel>
                </Border>

                <Border Background="#111722" CornerRadius="10" Padding="12" Margin="0,10,0,0">
                  <StackPanel>
                    <TextBlock Text="RESHADE LOOKS" Style="{StaticResource Eyebrow}"/>
                    <TextBlock x:Name="TxtReshadeList" Style="{StaticResource Hint}" Margin="0,4,0,0" Foreground="{StaticResource InkBrush}"/>
                    <Button x:Name="BtnOpenReshadeLib" Content="Open folder" Style="{StaticResource Ghost}"
                            HorizontalAlignment="Left" Margin="0,8,0,0"/>
                    <Grid Margin="0,8,0,0">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="8"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBox x:Name="TxtReshadeName" Style="{StaticResource DarkText}"/>
                      <Button x:Name="BtnSaveReshade" Grid.Column="2" Content="Capture current" Style="{StaticResource Ghost}" Height="30"/>
                    </Grid>
                  </StackPanel>
                </Border>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Padding="18">
              <StackPanel>
                <TextBlock Text="Safe switching" Style="{StaticResource SectionTitle}"/>
                <TextBlock Style="{StaticResource Hint}"
                           Text="FiveM must be closed. Packs are hash-verified before the swap, and a recovery journal restores the last complete setup if Windows stops halfway through."/>
                <Button x:Name="BtnReshadeManager" Content="Open ReShade manager" Style="{StaticResource Ghost}"
                        HorizontalAlignment="Left" Margin="0,10,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </Grid>

      <Border Grid.Row="2" Background="#111722" BorderBrush="#232D42" BorderThickness="1" CornerRadius="9"
              Padding="12,8" Margin="0,12,0,0">
        <TextBlock x:Name="PlayStatus" FontSize="11.5" Foreground="{StaticResource MutedBrush}"
                   Text="Ready. Choose a profile or create a new one." TextWrapping="Wrap"/>
      </Border>
    </Grid>

    <!-- ===================== SETUP: choose ===================== -->
    <Grid Grid.Row="2" x:Name="SetupScreen" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="390"/>
          <ColumnDefinition Width="14"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Style="{StaticResource Card}">
          <DockPanel>
            <DockPanel DockPanel.Dock="Top" LastChildFill="True" Margin="0,0,0,2">
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                <Button x:Name="BtnAll" Content="All" Style="{StaticResource Ghost}" Margin="0,0,6,0"/>
                <Button x:Name="BtnNone" Content="None" Style="{StaticResource Ghost}"/>
              </StackPanel>
              <TextBlock Text="Your apps" Style="{StaticResource SectionTitle}" VerticalAlignment="Center"/>
            </DockPanel>
            <TextBlock DockPanel.Dock="Top" Style="{StaticResource Hint}" Margin="0,2,0,10"
                       Text="These install silently in the background - no clicking through installers. Anything already on the PC is skipped."/>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel x:Name="AppsPanel"/>
            </ScrollViewer>
          </DockPanel>
        </Border>

        <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto">
          <StackPanel>

            <Border Style="{StaticResource Card}" Margin="0,0,0,12">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Margin="0,0,14,0">
                  <TextBlock Text="Drivers" Style="{StaticResource SectionTitle}"/>
                  <TextBlock Style="{StaticResource Hint}"
                             Text="Runs everything you've put in the Drivers folder - graphics, chipset, and so on. Zips are unpacked for you. Each installer opens one at a time: just click Next through it and the next one starts automatically."/>
                  <DockPanel Margin="0,10,0,0" LastChildFill="True">
                    <Button x:Name="BtnOpenDrivers" Content="Open Drivers folder" Style="{StaticResource Ghost}" DockPanel.Dock="Left"/>
                    <TextBlock x:Name="TxtDriversPath" FontSize="11" Foreground="{StaticResource MutedBrush}"
                               VerticalAlignment="Center" Margin="10,0,0,0" TextTrimming="CharacterEllipsis"/>
                  </DockPanel>
                  <Border Background="#11161E" BorderBrush="#232A36" BorderThickness="1" CornerRadius="10"
                          Padding="12" Margin="0,12,0,0">
                    <StackPanel>
                      <TextBlock Text="Detected on this PC" FontSize="12.5" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtHw" Style="{StaticResource Hint}" Margin="0,6,0,0" Text="Scanning..."/>
                      <StackPanel x:Name="HwToolsPanel" Margin="0,10,0,0"/>
                      <TextBlock Style="{StaticResource Hint}" Margin="0,8,0,0"
                                 Text="Need an exact driver version instead? Put its installer in the Drivers folder above - that always runs too."/>
                    </StackPanel>
                  </Border>
                </StackPanel>
                <CheckBox x:Name="SwDrivers" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="False" VerticalAlignment="Top"/>
              </Grid>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,12">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Margin="0,0,14,0">
                  <TextBlock Text="Fix mouse feel" Style="{StaticResource SectionTitle}"/>
                  <TextBlock Style="{StaticResource Hint}"
                             Text="Turns off Windows mouse acceleration ('Enhance Pointer Precision') so your aim moves the same distance every time. Applied instantly - no restart needed."/>
                </StackPanel>
                <CheckBox x:Name="SwMouse" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="False" VerticalAlignment="Top"/>
              </Grid>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,12">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Margin="0,0,14,0">
                  <TextBlock Text="FiveM" Style="{StaticResource SectionTitle}"/>
                  <TextBlock Style="{StaticResource Hint}"
                             Text="Downloads FiveM and opens its installer at the end - you just pick where it goes."/>
                </StackPanel>
                <CheckBox x:Name="SwFiveM" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="True" VerticalAlignment="Top"/>
              </Grid>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,12">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Margin="0,0,14,0">
                  <TextBlock Text="ReShade for FiveM" Style="{StaticResource SectionTitle}"/>
                  <TextBlock Style="{StaticResource Hint}"
                             Text="Adds ReShade to FiveM for better graphics (toggle in game with the Home key). FiveM needs to have been opened once first - if it hasn't, this step will tell you, and you just run the app again after. Got a ReShadePayload.zip next to this app? Your exact saved setup gets restored instead."/>
                </StackPanel>
                <CheckBox x:Name="SwReshade" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="True" VerticalAlignment="Top"/>
              </Grid>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,0,0,12">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Margin="0,0,14,0">
                  <TextBlock Text="Backup and restore" Style="{StaticResource SectionTitle}"/>
                  <TextBlock Style="{StaticResource Hint}"
                             Text="Before a wipe: press Back up now and your browser bookmarks (Brave, Chrome or Edge) and your FiveM settings (the CitizenFX folder) are saved next to this app. After a wipe: leave the switch on and they're put back as part of setup."/>
                  <TextBlock x:Name="TxtBackupInfo" Style="{StaticResource Hint}" Margin="0,8,0,0" FontSize="12"
                             Foreground="{StaticResource InkBrush}" Text="No backup here yet."/>
                  <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                    <Button x:Name="BtnBackupNow" Content="Back up now" Style="{StaticResource PrimarySm}"/>
                    <Button x:Name="BtnOpenBackup" Content="Open backup folder" Style="{StaticResource Ghost}" Margin="8,0,0,0" VerticalAlignment="Center"/>
                    <Button x:Name="BtnExportPw" Content="Export passwords..." Style="{StaticResource Ghost}" Margin="8,0,0,0" VerticalAlignment="Center"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Hint}" Margin="0,10,0,0"
                             Text="Passwords can't be copied as files - Windows locks them to the old install, so they'd come back unreadable. Export passwords opens your browser's page for it: save the CSV into the Backup folder, then import it the same way after the wipe. (Or turn on Brave Sync and skip all that.)"/>
                </StackPanel>
                <CheckBox x:Name="SwRestore" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="False" IsEnabled="False" VerticalAlignment="Top"/>
              </Grid>
            </Border>

            <Border Style="{StaticResource Card}">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Margin="0,0,14,0">
                  <TextBlock Text="Open apps when done" Style="{StaticResource SectionTitle}"/>
                  <TextBlock Style="{StaticResource Hint}"
                             Text="When everything's installed, your apps open by themselves - all that's left for you is signing in."/>
                </StackPanel>
                <CheckBox x:Name="SwLaunch" Grid.Column="1" Style="{StaticResource Switch}" IsChecked="False" VerticalAlignment="Top"/>
              </Grid>
            </Border>

          </StackPanel>
        </ScrollViewer>
      </Grid>

      <Grid Grid.Row="1" Margin="0,16,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Button x:Name="BtnRun" Grid.Column="0" Content="Set up my PC" Style="{StaticResource Primary}" Width="190"/>
        <TextBlock x:Name="FooterHint" Grid.Column="1" FontSize="11.5" Foreground="{StaticResource MutedBrush}"
                   VerticalAlignment="Center" Margin="16,0" TextWrapping="Wrap"
                   Text="Flick anything off that you don't want. You'll see progress on the next screen."/>
        <Button x:Name="BtnConfig" Grid.Column="2" Content="Edit app list" Style="{StaticResource Ghost}" VerticalAlignment="Center"/>
      </Grid>
    </Grid>

    <!-- ===================== SETUP: progress ===================== -->
    <Grid Grid.Row="2" x:Name="ProgressScreen" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <TextBlock Grid.Row="0" x:Name="PTitle" Text="Setting up your PC..." FontSize="20" FontWeight="SemiBold" Margin="2,0,0,10"/>
      <ProgressBar Grid.Row="1" x:Name="PBar" Height="6" Background="#1B212B"
                   Foreground="{StaticResource AccentBrush}" BorderThickness="0" Margin="0,0,0,12"/>

      <Border Grid.Row="2" x:Name="DoneBanner" Background="#14261C" BorderBrush="#2E5C42" BorderThickness="1"
              CornerRadius="10" Padding="14,10" Margin="0,0,0,12" Visibility="Collapsed">
        <TextBlock x:Name="DoneText" Foreground="#3EE6A8" FontSize="13"
                   Text="You're set up. Sign in to your apps as they open." TextWrapping="Wrap"/>
      </Border>

      <Border Grid.Row="3" Style="{StaticResource Card}">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="TasksPanel"/>
        </ScrollViewer>
      </Border>

      <Button Grid.Row="4" x:Name="BtnDetails" Content="Show details" Style="{StaticResource Ghost}"
              HorizontalAlignment="Left" Margin="0,10,0,0"/>

      <Border Grid.Row="5" x:Name="LogCard" Style="{StaticResource Card}" Padding="10" Height="170"
              Margin="0,10,0,0" Visibility="Collapsed">
        <RichTextBox x:Name="LogBox" Background="Transparent" BorderThickness="0" Foreground="#C9D1D9"
                     FontFamily="Cascadia Mono, Consolas" FontSize="12" IsReadOnly="True"
                     VerticalScrollBarVisibility="Auto"/>
      </Border>

      <Grid Grid.Row="6" Margin="0,14,0,0">
        <Button x:Name="BtnBack" Content="Back" Style="{StaticResource Primary}" Width="190"
                HorizontalAlignment="Left" IsEnabled="False"/>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@

try {
    $script:Window = [Windows.Markup.XamlReader]::Parse($Xaml)
}
catch {
    [Windows.MessageBox]::Show("The app window failed to load:`n`n$($_.Exception.Message)", 'Xn Fresh Deploy') | Out-Null
    exit 1
}

foreach ($name in 'NavPlay','NavSetup','PlayScreen','ServersPanel','NoServersText','NoServersTitle','NoServersHint','TxtProfileSummary','TxtLibrarySummary',
                  'TxtNewName','TxtNewConnect','CmbNewSound','CmbNewReshade','LstNewCommands','TxtNewCommandSummary','PnlNewMouseScale','TxtNewMouseScale','PnlNewFov','TxtNewFov',
                  'TxtNewCustomName','TxtNewCustomValue','BtnAddNewCustom','BtnRemoveNewCustom','TxtNewCustomStatus','BtnTestServer','BtnDetectServer','BtnAddServer',
                  'BtnImportProfiles','BtnPortableProfiles','BtnExportProfiles','BtnRestorePrevious','TxtProfileSearch','CmbProfileSort','BtnManageLibraries','BtnRefreshLibraries',
                  'TxtSoundList','BtnOpenSounds','TxtSoundName','BtnSaveSound','TxtReshadeList',
                  'BtnOpenReshadeLib','TxtReshadeName','BtnSaveReshade','BtnReshadeManager','PlayStatus',
                  'SetupScreen','ProgressScreen','AppsPanel','BtnAll','BtnNone','SwDrivers','TxtDriversPath',
                  'BtnOpenDrivers','TxtHw','HwToolsPanel','SwMouse','SwFiveM','SwReshade','SwLaunch','BtnConfig','BtnRun','FooterHint',
                  'SwRestore','TxtBackupInfo','BtnBackupNow','BtnOpenBackup','BtnExportPw',
                  'PTitle','PBar','DoneBanner','DoneText','TasksPanel','BtnDetails','LogCard','LogBox','BtnBack') {
    Set-Variable -Name $name -Value $Window.FindName($name) -Scope Script
}

Initialize-ProfileCommandPicker $LstNewCommands @() $TxtNewMouseScale $TxtNewFov
Update-ProfileCommandPicker $LstNewCommands $PnlNewMouseScale $PnlNewFov $TxtNewCommandSummary
$LstNewCommands.Add_SelectionChanged({
    param($s, $e)
    Update-ProfileCommandPicker $s $script:PnlNewMouseScale $script:PnlNewFov $script:TxtNewCommandSummary $e
})
$BtnAddNewCustom.Add_Click({
    try {
        $item = Add-CustomProfileCommandToPicker $script:LstNewCommands $script:TxtNewCustomName $script:TxtNewCustomValue
        Update-ProfileCommandPicker $script:LstNewCommands $script:PnlNewMouseScale $script:PnlNewFov $script:TxtNewCommandSummary
        $script:TxtNewCustomStatus.Text = "Added and selected: $($item.Name) $($item.Value)"
    }
    catch { $script:TxtNewCustomStatus.Text = $_.Exception.Message }
})
$BtnRemoveNewCustom.Add_Click({
    $removed = Remove-SelectedCustomProfileCommands $script:LstNewCommands
    Update-ProfileCommandPicker $script:LstNewCommands $script:PnlNewMouseScale $script:PnlNewFov $script:TxtNewCommandSummary
    $script:TxtNewCustomStatus.Text = if ($removed -gt 0) { "Removed $removed custom command(s)." } else { 'Select a Custom entry in the command list first.' }
})

# --- Window / taskbar icon (embedded) -------------------------------------------
$IconB64 = 'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAANIklEQVR4nN2bbYwd1XnHf8+Zuffum9cvFGMDIZQ0NnEsh/BSwG6w3aYG00CVkl3y0lJEEqK2ogjROHyodLNqv6SqFKRI+QAObXCTlN0EQpASp5hsIFCakhdwbIMDEbRGAQfZa9nel3vvzHn64czcOXfuzF3bbSV2j3Q1szPnOef5/5+X85yz9wqn0UZGNFi3DjlwAJ2YkPh0ZP+/W72uBjAH3otOjGJB9FTk5FQ6jYxoMDHROehdd2n/8DC1Y8Ay4Njp65y1Zf87WXsc+6U75bj/eGRcg1MhoicBqioAIm6QHTt0owRss8pG4D1iGFIFKwjiRtN0VAFNR0/vk78L700mm38vybjt+3RcgyqIGiIx7BfDz1Emgya7v3SnNMB5xtiY2NMmwBe85x79mDHcoXB1tQqxQhTnFPbBFBGRe15IQhlpRXK5OUwFTAhqIbK8ZJWvH3mdL0yMSdN5Q3HIFhLgXF7iz/6VnhsOsTOssF0FGk0UiDGIgiBImYV8IHjPBO/ekyMHrNe4/hhk81gVFEGCKkFYg1aT/c0Gn/nKX8gzmyc1fHKrRPMSkIK/+269oq/Co0GF1XMN4kS5oMha81qe4vuecmfgBd57q2ArfYQqRK0mf7nzU3J/kScY/496Xc3EhMQ77tLf7avyfQyrZ+eIEIK3PfjOqxFD2GoQxy2C6gD33bZTPz0xKvHIuAY+5rYHJMsI09OsrAS8YAJWNiNiMQRdQN+O4HN92jKgEmDDPoLmLNu+cps87ntChweMjYk1ylcrVVY2W0QLFrzXF4NYReIINSG7Pv5lXT4+giVZ4QzA+LgGY2Ni7/ms3lzrZ9tcg0gM4YIFT+e9GEzUwlYGOKdvgL8TER2ZcNgNwP79qKqKVXYkE0jXxAsUfConBtOcRSXkk5/YpasnRiVGVcLxcQ1GRyVuTOvVYZX3NVpYWQgJ71TBZ2NIbIlqS+izJ/kz4B9uv4/Q7NnjvCAyXF+pEgB2EYJ3XiCIVVDD9aoqU8uxZmoKi3ORK2IFDLLowGdXE7cAYf0nH2VoYlRiMzGBrdd1CFiflLdm0YFPxzGIjdGwxrLWDGsBDIj+pkFFheHTru0XEPj0uQWVkMAISxMCoFpDRdrl7qIF3x4XMAER4Nb6BIBobpBTAT/fru//Avx8wE6ljw9eJdnCdxCA1wqUwYB4AxjnTj2BISCms097h5eTE9PO1O0x2nP0ACbeVSXDUUqqR0QHAemgvpKpYpGFVsOR4L8PQwjCnJLevQWazW5rmQAqlUzOatYvb7VKBYISsq1CM+6cWwxUwhLwHoFdBBSxJAYaLdi+Fda+C+I4sai6Q5Hx3XD4KFSqoNoNvhLCbTfAUH9mGRE4egJ2PZGNv/YdcOOVbgzxlIxi+OpTcGTake2fDczFsHYV3HSZk0Pc1DMtuP9ZmIsSnPnwVI+IvAfkP5qQsPcgXLfFuaTfbt4O936tm2kTwPQM/MkWuHQNXW3nbphtOWIihSUDsPa87n4A114CDzwJS6rO4imJscKSfrh4VWf/loXAOAMEefB49wnybDdYEJuqUK3Brw7BNx5z3aLYKRLHsPZC+OBVcHIWgiAjbHoONrwbfv8yiC1Y6+QAfrgXntoHA30OBJL0URdqVr2PhWsuhgvPTiyaAxRrJpfezzQL8kYevGfINgFl2Ty2MDwET/8M9v4SwsB1NoEj6IZr4J3nOouawPUfHICP/2EyQeKyYQC/OQbfesaBt+opY1y//AeBSgB/9H5oxVmi80GUyc23SqRnYx0eQG5wPxmFFXjoe3BiJrFEEvPVCnziOvdMcETctAXOXuYs2M76Cv/yA5huuMTZtaYXNJN44ZUXwZrVMBuBMd3guto84DvmmFcI51LVCrx1DL75eAJKk2XKwkXnwfWb4M0puPxi+MAGZ2Fj3Hsj8MTz8MJrndbvBR6ykAwM3HiJ00N9uRL5+cD785q8kJYQEalz7Wf3wk8OZODEODK2XwWbNsBNmzPdNCHh10fg4X+H/iLwPSwpZF7w/gtg/Xkuy5v5yJsPfFkSLBvAD4VqFcb3wLETWSikMX7HTbByeTJE0j+28OAPXBILTLcF866cLpdTM3DoqLtPs/8fX+IILUpm+dYLfKEHdAgVgE/X9rACUyfhX/d4a7Y/RnJNXX/3T+HAocT1KQavBQM0I/j284mS4kh4zyq49AKYbiVEnAH4PGndIVACPl0lrMLAADz3EjzzC0eC9TTxXf+1w/CdH8Ngv1umem5scm2wBi+8Ds8fynIOwIc3uAKrvdQVNen0tDyOYg/IxWSvDYoq9NdgfBKmTmRx6rcohgcn3RrdYa0i8GWeZODbe5OEmhB94Vmw8bdhupmsCAXgi1ayPI5OApZlnfM7wqJaWgQaMVywCgZquRI2aYGBd5/rkiemm9jCLa1PgEJ/FV58E37y352eduN6N29cEgNllu8gJ58E89vgMvDpitDfB7dsg1q1U2k8mY9sggvPgdlmslqUgS9x5XTD9egvXCEUJCSsWgKb3+VyQVnr6cFlIXAq+3kJHKCPbM4VO54XpHmgEsCfb02WTLrH6lnM4GRqFfjVEXj61WweBW54LyzrS4bKjdETR9K3qxJUr8LqBX56zm1wrvGKnXQf/+ph96y9l7dw0TnwoctdBdiO2Xniv90SXaohPLYf5pLsj8L5w7BtjZuva4gyHH5o5AnoSA5FScq4xDY8BB/7g+yxJgq8cRT+fhyee9n9bdW5vVX40KWwJi1izOl7QbUCh47DE68kcybvLj67e4eaJ6IQfCEBlFu+vQdvwegWOGs4AShesTPp4vShZ2BqmqxIwhVJt17jlq+4SLGiJOjpY4G+Cnz3IJxodIZCUetp+dxc5aWwB94EcLIBV66Dq9dlRU56/f7PYN8hWDoER07C136UWSrN3hecBR9OQiHIVXNlQPz31RAOT8P3XvbG7iFXVtK37wtL4VwYpJZvRbBiGD66NUt2abHzX2/Bo//pip2WddcfvwI/eilbu9Pr9g2w/h1wMl3Dcxk5j923YIxbFh9/BY7M0FEclRFXCr4sBxTGpnHb0Ju3wNJB5+5KchARw65JaHrFjlXoq8E3noW3jjtFY5spe8tGl9kjz4QquYMQ9SrHtA9uVTk6B4/90j2OtVvO5uUK7ot3g2Sd0o5iYKYB114OV6x178PAWTQw8NhzcPANryhJZIMkZP75aTd3YNzHCJy/HG7d5A4z0wMOk7wLvX4DlW7FY2CwCpOvwZsnXf/0ECSQTK7ru0d58B4BPc8EY4WhQXdoefD1jCgROHICdj8Pg97RVjv21JGy9xA8/FNYd14WOlbht4bg/BXw5glH1vE5ePFwlrwEV+p2WDMBZQxMR/D1fXDd72Qhluo1EznvkjLw0EGAANz5RV0WWV4zIUutRZNvgbVDoBklOzk6lalVO1ktXDmiYkvUKp5l1eWP/MpQDbut1s5LNilm8q7uy/n6ZnrbcAATN9n60Fb5YZcHFNXo1Uq3JUS87W2JnAJ91Y7J227frgwTq/alZ/lkYVjqxrgSuVIwb1uuADyJd/YOAbqF/K9ZqnftubHxlOmS88D3mqMwk0vxWB1yZeC952kp7P9vsJPxAqGe+/mS96VyRUrmgZaB7yVHTre8HJ4+PgE+a4sWfI4IOIPd4IIG7+lTdB7Q/mbYYgefJEtpE9DXQNXQwuu0qMErKpHLg2ZkRIMvfI7jCC8GrvqyixY8qAkx8RwnG8qLAGb5BzGIKMLPTYiqeHuMxQTefdTUwMIr/W8xVa+rMQd/7WSs8rhVBD8XLCLwyXNraiDC5MSoxG/cQGCeHJNIURmcY09jjleDKkaTMFhU4AE1mHiW2Eb8E8Dqy4gNwOg45ot3y6wKO8MaoiR5gEUCXsAKcWUQEzV54pGtsq+uasZErAGYGMHW62pWr+AfZ2d4udJHqJp9bW6hg1dQCcC2iCPhr/GaqwNElM/D2Kg0FW6xikqIKOm36hc0eBSi2nKCqMHffOf35ODIuAZj4n4Q1i6ExkTsyLgGO2+X/2g2+UzYh5HAHbIsYPAKtGorqMxNcf8jH5B7878bSkXbrT6p4dhWiW7bqZ/uG+S+KIIoIhIh6DgneBuDT6wei8FUVyCNY9z/8Ea5va5qxkAR8dNbd9tc1/DJMYlufUCvrVZ5IOzj3MYsWCUSEBVM+q3y0y6be5BzpqSm1lb3szmLEIaDYGOaGvO5b14l9xaBLyUA0p+eSvynX9aV/Uv5Wwy3hjWWWIWoBTZGrZuwW7EzIaVEridR3r0JMaYGpgrRHLHCv8UROx7ZJPuoq2EMpeBntKUE+CQAfGqXni8hH42F7Wp5nwk5y1Q7lexlKf806ExCo+fYCnGD44QcFOEpW+HBb10me/MYilpPAtxsKiMTGH+QO76rw9PHWCP9DEVz5E8VAIgKnhX1I8xOZ+brByV9Y+KBlRzYtU6O+HrXP4/0+t3wabV6XU19UsP094Vvz6ayeVLDup66jv8DIBMkDilMvtcAAAAASUVORK5CYII='
try {
    $iconBytes = [Convert]::FromBase64String($IconB64)
    $ms = New-Object System.IO.MemoryStream(,$iconBytes)
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.StreamSource = $ms
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.EndInit()
    $bmp.Freeze()
    $Window.Icon = $bmp
} catch {}

$TxtDriversPath.Text = $DriversDir
$SwDrivers.IsChecked = [bool](Get-ChildItem -LiteralPath $DriversDir -File -ErrorAction SilentlyContinue |
                               Where-Object { $_.Extension.ToLowerInvariant() -in '.zip','.7z','.rar','.exe','.msi' } |
                               Select-Object -First 1)

# --- Details log -------------------------------------------------------------------
$script:LogPara = New-Object System.Windows.Documents.Paragraph
$LogPara.Margin = New-Object System.Windows.Thickness(0)
$doc = New-Object System.Windows.Documents.FlowDocument
$doc.Blocks.Add($LogPara)
$LogBox.Document = $doc

function Add-LogLine([string]$Level, [string]$Msg) {
    $color = switch ($Level) {
        'OK'    { '#3EE6A8' }
        'FAIL'  { '#FF5C6C' }
        'WARN'  { '#FFC14D' }
        'STEP'  { '#9D8FFF' }
        default { '#C9D1D9' }
    }
    $text = switch ($Level) {
        'STEP'  { "`r`n=== $Msg ===" }
        'OK'    { "[ ok ] $Msg" }
        'FAIL'  { "[fail] $Msg" }
        'WARN'  { "[warn] $Msg" }
        default { "[ .. ] $Msg" }
    }
    $run = New-Object System.Windows.Documents.Run("$text`r`n")
    $run.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($color))
    $script:LogPara.Inlines.Add($run)
    $script:LogBox.ScrollToEnd()
}

function Clear-Log { $script:LogPara.Inlines.Clear() }

function New-Brush([string]$Hex) {
    return New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
}

function Pump-MainUi { $script:Window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }

# ==============================================================================
#  Navigation
# ==============================================================================
$script:Running = $false

function Set-Nav([string]$Tab) {
    if ($Tab -eq 'play') {
        $script:NavPlay.Style  = $Window.Resources['NavOn']
        $script:NavSetup.Style = $Window.Resources['NavOff']
        $script:PlayScreen.Visibility     = 'Visible'
        $script:SetupScreen.Visibility    = 'Collapsed'
        $script:ProgressScreen.Visibility = 'Collapsed'
    }
    else {
        $script:NavPlay.Style  = $Window.Resources['NavOff']
        $script:NavSetup.Style = $Window.Resources['NavOn']
        $script:PlayScreen.Visibility = 'Collapsed'
        if ($script:Running) {
            $script:SetupScreen.Visibility    = 'Collapsed'
            $script:ProgressScreen.Visibility = 'Visible'
        } else {
            $script:SetupScreen.Visibility    = 'Visible'
            $script:ProgressScreen.Visibility = $script:ProgressScreen.Visibility
            if ($script:ProgressScreen.Visibility -ne 'Visible') { $script:ProgressScreen.Visibility = 'Collapsed' }
            # If a finished progress view is showing, keep it until Back is pressed
            if ($script:ProgressScreen.Visibility -eq 'Visible') { $script:SetupScreen.Visibility = 'Collapsed' }
        }
    }
}

$NavPlay.Add_Click({ Set-Nav 'play' })
$NavSetup.Add_Click({ Set-Nav 'setup' })

# ==============================================================================
#  PLAY tab
# ==============================================================================
$script:UiLoading = $false
$script:SoundOptions   = @('None')
$script:ReshadeOptions = @('Keep current')
foreach ($option in 'Last played','Server name','Favourites','Online status') { [void]$script:CmbProfileSort.Items.Add($option) }
$script:CmbProfileSort.SelectedIndex = 0
$script:TxtProfileSearch.Add_TextChanged({ if (-not $script:UiLoading) { Rebuild-ServerRows } })
$script:CmbProfileSort.Add_SelectionChanged({ if (-not $script:UiLoading) { Rebuild-ServerRows } })

function Get-ServerByName([string]$Name) {
    return ($script:Servers | Where-Object { [string]$_.name -eq $Name } | Select-Object -First 1)
}

function Refresh-Libraries {
    $packs = @(Get-ChildItem $script:SoundLibDir -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike '_*' -and $_.Name -notlike '.*' } | Sort-Object Name | ForEach-Object Name)
    $looks = @(Get-ChildItem $script:ReshadeLibDir -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notlike '_*' -and $_.Name -notlike '.*' } | Sort-Object Name | ForEach-Object Name)
    $script:SoundOptions   = @('None') + $packs
    $script:ReshadeOptions = @('Keep current') + $looks

    $soundChoice = [string]$script:CmbNewSound.SelectedItem
    $reshadeChoice = [string]$script:CmbNewReshade.SelectedItem
    $script:CmbNewSound.Items.Clear()
    $script:CmbNewReshade.Items.Clear()
    foreach ($o in $script:SoundOptions) { [void]$script:CmbNewSound.Items.Add($o) }
    foreach ($o in $script:ReshadeOptions) { [void]$script:CmbNewReshade.Items.Add($o) }
    $script:CmbNewSound.SelectedItem = if ($script:SoundOptions -contains $soundChoice) { $soundChoice } else { 'None' }
    $script:CmbNewReshade.SelectedItem = if ($script:ReshadeOptions -contains $reshadeChoice) { $reshadeChoice } else { 'Keep current' }

    $script:TxtSoundList.Text = if ($packs.Count -gt 0) {
        "$($packs.Count) available - $($packs -join ', ')"
    } else { 'No soundpacks saved yet.' }
    $script:TxtReshadeList.Text = if ($looks.Count -gt 0) {
        "$($looks.Count) available - $($looks -join ', ')"
    } else { 'No looks saved yet.' }
    $script:TxtLibrarySummary.Text = "$($packs.Count) packs / $($looks.Count) looks"
}

function Get-LibraryRoot([string]$Kind) {
    if ($Kind -eq 'Soundpack') { return $script:SoundLibDir }
    if ($Kind -eq 'ReShade') { return $script:ReshadeLibDir }
    throw "Unknown library kind: $Kind"
}

function Get-LibraryExclusions([string]$Kind) {
    if ($Kind -eq 'Soundpack') { return @('.xn-current') }
    return @('dxgi.dll','d3d11.dll','.xn-reshade','.xn-reshade-files.json','.xn-reshade-base.json')
}

function Get-LibraryImportPreview([string]$Kind, [string]$Source) {
    if (-not (Test-Path $Source -PathType Container)) { throw 'Choose a folder to preview.' }
    $excluded = Get-EffectiveExclusions (Get-LibraryExclusions $Kind)
    $files = @(Get-ChildItem $Source -Recurse -Force -File -ErrorAction Stop | Where-Object { $excluded -notcontains $_.Name })
    $riskyExtensions = @('.exe','.msi','.com','.scr','.bat','.cmd','.ps1','.psm1','.vbs','.vbe','.js','.jse','.wsf','.wsh','.dll','.asi')
    $risky = @($files | Where-Object { $riskyExtensions -contains $_.Extension.ToLowerInvariant() } |
               ForEach-Object { Get-RelativeChildPath $Source $_.FullName })
    $groups = @($files | Group-Object { if ($_.Extension) { $_.Extension.ToLowerInvariant() } else { '[no extension]' } } |
                Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Ascending = $true })
    $shownGroups = @($groups | Select-Object -First 20)
    $types = if ($shownGroups.Count -gt 0) { @($shownGroups | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ' } else { 'none' }
    if ($groups.Count -gt $shownGroups.Count) { $types += ", plus $($groups.Count - $shownGroups.Count) more type(s)" }
    [int64]$bytes = 0
    foreach ($file in $files) { $bytes += $file.Length }
    return [pscustomobject]@{ Files = $files.Count; Bytes = $bytes; Types = $types; Risky = $risky }
}

function Confirm-LibraryImport($Owner, [string]$Kind, [string]$Source) {
    $preview = Get-LibraryImportPreview $Kind $Source
    if ($preview.Files -eq 0) {
        [Windows.MessageBox]::Show($Owner, 'That folder has no usable files.', 'Import preview', 'OK', 'Information') | Out-Null
        return $false
    }
    $size = if ($preview.Bytes -ge 1GB) { '{0:N2} GB' -f ($preview.Bytes / 1GB) }
            elseif ($preview.Bytes -ge 1MB) { '{0:N1} MB' -f ($preview.Bytes / 1MB) }
            else { '{0:N0} KB' -f ([Math]::Max(1, $preview.Bytes / 1KB)) }
    $message = "Import '$(Split-Path $Source -Leaf)' as a $Kind?`n`n$($preview.Files) files - $size`nFile types: $($preview.Types)"
    $icon = 'Question'
    if ($preview.Risky.Count -gt 0) {
        $shown = @($preview.Risky | Select-Object -First 8)
        $more = if ($preview.Risky.Count -gt $shown.Count) { "`n...and $($preview.Risky.Count - $shown.Count) more" } else { '' }
        $message += "`n`nWarning: executable, script, or DLL files were found:`n$($shown -join "`n")$more`n`nOnly continue if you trust where this pack came from."
        $icon = 'Warning'
    }
    return ([Windows.MessageBox]::Show($Owner, $message, 'Import preview', 'YesNo', $icon) -eq 'Yes')
}

function Import-LibraryFolder([string]$Kind, [string]$Source, [string]$Name = '') {
    if (-not (Test-Path $Source -PathType Container)) { throw 'Choose a folder to import.' }
    if (-not $Name) { $Name = Split-Path $Source -Leaf }
    $Name = $Name.Trim()
    if (-not (Test-LibraryName $Name)) { throw 'Use letters, numbers, spaces, dashes, or dots for the pack name (max 30; do not start with a dot or underscore).' }

    $root = Get-LibraryRoot $Kind
    $destination = Get-SafeChildPath $root $Name
    if (Test-Path $destination) { throw "$Kind '$Name' already exists." }
    $stage = Join-Path $root ("._xn-import-" + [Guid]::NewGuid().ToString('N'))
    $excluded = Get-LibraryExclusions $Kind
    try {
        Copy-DirectoryContents $Source $stage $excluded
        Assert-TreesMatch $Source $stage $excluded
        $stats = Get-TreeStats $stage
        if ($stats.Files -eq 0) { throw 'The selected folder has no usable files.' }
        Move-Item -LiteralPath $stage -Destination $destination -Force
        [void](Get-TreeHashManifest $destination $excluded $false $true)
        return [pscustomobject]@{ Name = $Name; Files = $stats.Files; Bytes = $stats.Bytes }
    }
    finally {
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Rename-LibraryItem([string]$Kind, [string]$OldName, [string]$NewName) {
    $NewName = $NewName.Trim()
    if (-not (Test-LibraryName $NewName)) { throw 'Use letters, numbers, spaces, dashes, or dots for the new name (max 30).' }
    $root = Get-LibraryRoot $Kind
    $source = Get-SafeChildPath $root $OldName
    $destination = Get-SafeChildPath $root $NewName
    if (-not (Test-Path $source -PathType Container)) { throw "$Kind '$OldName' is missing." }
    if (Test-Path $destination) { throw "$Kind '$NewName' already exists." }
    Move-Item -LiteralPath $source -Destination $destination
    $property = if ($Kind -eq 'Soundpack') { 'soundpack' } else { 'reshade' }
    foreach ($server in $script:Servers) {
        if ([string]$server.$property -eq $OldName) { Set-Prop $server $property $NewName }
    }
    Save-Servers
}

function Get-LibraryItems([string]$Kind) {
    $root = Get-LibraryRoot $Kind
    $property = if ($Kind -eq 'Soundpack') { 'soundpack' } else { 'reshade' }
    $usage = @{}
    foreach ($server in $script:Servers) {
        $name = [string]$server.$property
        if (-not $usage.ContainsKey($name)) { $usage[$name] = New-Object System.Collections.ArrayList }
        [void]$usage[$name].Add([string]$server.name)
    }
    $items = @()
    foreach ($folder in Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notlike '_*' -and $_.Name -notlike '.*' } | Sort-Object Name) {
        $stats = Get-TreeStats $folder.FullName
        $usedBy = if ($usage.ContainsKey($folder.Name)) { @($usage[$folder.Name]) } else { @() }
        $useText = if ($usedBy.Count -eq 1) { 'used by 1 profile' } elseif ($usedBy.Count -gt 1) { "used by $($usedBy.Count) profiles" } else { 'unused' }
        $items += [pscustomobject]@{
            Name = $folder.Name
            Files = $stats.Files
            Bytes = $stats.Bytes
            UsedBy = @($usedBy)
            Display = "$($folder.Name)    -    $($stats.Files) files    -    $useText"
        }
    }
    return $items
}

function Save-CurrentSoundpack([string]$Name) {
    $mods = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app\mods'
    if (-not (Test-Path $mods -PathType Container)) { throw "FiveM's mods folder is missing - there's nothing to capture yet." }
    [void](Import-LibraryFolder 'Soundpack' $mods $Name)
}

function Save-CurrentReshade([string]$Name) {
    $plugins = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app\plugins'
    if (-not (Test-Path $plugins -PathType Container)) { throw 'No ReShade settings were found - set ReShade up in FiveM first.' }
    $result = Import-LibraryFolder 'ReShade' $plugins $Name
    $destination = Get-SafeChildPath $script:ReshadeLibDir $result.Name
    try {
        foreach ($relative in @(Get-ReShadeBaseProtectedFiles)) {
            $file = Get-SafeChildPath $destination $relative
            if (Test-Path $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force }
        }
        $cache = Join-Path $destination $script:IntegrityFileName
        if (Test-Path $cache) { Remove-Item -LiteralPath $cache -Force }
        $stats = Get-TreeStats $destination (Get-LibraryExclusions 'ReShade')
        if ($stats.Files -eq 0) { throw 'No preset-specific ReShade files were found. Save or select a preset in ReShade first.' }
        [void](Get-TreeHashManifest $destination (Get-LibraryExclusions 'ReShade') $false $true)
    }
    catch {
        if (Test-Path $destination) { Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Show-NamePrompt($Owner, [string]$Title, [string]$Label, [string]$InitialValue = '') {
    $promptXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="430" Height="235" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
        Background="#0B0F17" FontFamily="Segoe UI">
  <Grid Margin="22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock x:Name="PromptTitle" Foreground="#E6EDF3" FontSize="18" FontWeight="SemiBold"/>
    <TextBlock x:Name="PromptLabel" Grid.Row="1" Foreground="#8B949E" FontSize="11.5" Margin="0,7,0,8"/>
    <TextBox x:Name="PromptValue" Grid.Row="2" Height="36" VerticalAlignment="Top"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="PromptCancel" Content="Cancel" Margin="0,0,8,0"/>
      <Button x:Name="PromptOk" Content="Save"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $prompt = [Windows.Markup.XamlReader]::Parse($promptXaml)
    $prompt.Owner = $Owner
    $prompt.Title = $Title
    $titleText = $prompt.FindName('PromptTitle'); $titleText.Text = $Title
    $labelText = $prompt.FindName('PromptLabel'); $labelText.Text = $Label
    $value = $prompt.FindName('PromptValue'); $value.Text = $InitialValue; $value.Style = $Window.Resources['DarkText']
    $cancel = $prompt.FindName('PromptCancel'); $cancel.Style = $Window.Resources['Ghost']
    $ok = $prompt.FindName('PromptOk'); $ok.Style = $Window.Resources['PrimarySm']
    $state = @{ Value = $null }
    $cancel.Add_Click({ $prompt.DialogResult = $false })
    $ok.Add_Click({
        $text = $value.Text.Trim()
        if (-not (Test-LibraryName $text)) { $labelText.Text = 'Use letters, numbers, spaces, dashes, or dots (max 30).'; $labelText.Foreground = New-Brush '#FF8A96'; return }
        $state.Value = $text
        $prompt.DialogResult = $true
    })
    $value.Add_KeyDown({ param($s,$e) if ($e.Key -eq 'Enter') { $ok.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) } })
    [void]$prompt.ShowDialog()
    return $state.Value
}

function Show-LibraryManager {
    $managerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pack library" Width="760" Height="580" MinWidth="680" MinHeight="520"
        WindowStartupLocation="CenterOwner" Background="#0B0F17" FontFamily="Segoe UI">
  <Grid Margin="22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid Grid.Row="0" Margin="0,0,0,14">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="220"/></Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="PACK LIBRARY" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold"/>
        <TextBlock Text="Manage reusable FiveM packs" Foreground="#E6EDF3" FontSize="20" FontWeight="SemiBold" Margin="0,3,0,0"/>
        <TextBlock Text="Import folders, rename packs, and see which profiles depend on them." Foreground="#8B949E" FontSize="11.5" Margin="0,4,0,0"/>
      </StackPanel>
      <ComboBox x:Name="LibKind" Grid.Column="1" Height="36" VerticalAlignment="Center"/>
    </Grid>
    <Border x:Name="LibDrop" Grid.Row="1" AllowDrop="True" Background="#111A2A" BorderBrush="#4859A6" BorderThickness="1"
            CornerRadius="11" Padding="16,12" Margin="0,0,0,12">
      <TextBlock x:Name="LibDropText" Text="Drop a soundpack folder here, or use Import folder" Foreground="#AAB7D7"
                 FontSize="12" HorizontalAlignment="Center"/>
    </Border>
    <ListBox x:Name="LibList" Grid.Row="2" Background="#111722" Foreground="#E6EDF3" BorderBrush="#263149"
             BorderThickness="1" Padding="5" FontSize="12.5" DisplayMemberPath="Display"/>
    <Border Grid.Row="3" Background="#111722" BorderBrush="#263149" BorderThickness="1" CornerRadius="9" Padding="11,8" Margin="0,12,0,0">
      <TextBlock x:Name="LibStatus" Text="Choose a library and select a pack." Foreground="#8B949E" FontSize="11.5" TextWrapping="Wrap"/>
    </Border>
    <Grid Grid.Row="4" Margin="0,14,0,0">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="LibImport" Content="Import folder" Margin="0,0,8,0"/>
        <Button x:Name="LibRename" Content="Rename" Margin="0,0,8,0"/>
        <Button x:Name="LibDelete" Content="Delete"/>
      </StackPanel>
      <Button x:Name="LibClose" Content="Done" HorizontalAlignment="Right"/>
    </Grid>
  </Grid>
</Window>
'@
    $manager = [Windows.Markup.XamlReader]::Parse($managerXaml)
    $manager.Owner = $script:Window
    $kindBox = $manager.FindName('LibKind')
    $list = $manager.FindName('LibList')
    $drop = $manager.FindName('LibDrop')
    $dropText = $manager.FindName('LibDropText')
    $status = $manager.FindName('LibStatus')
    $import = $manager.FindName('LibImport')
    $rename = $manager.FindName('LibRename')
    $delete = $manager.FindName('LibDelete')
    $close = $manager.FindName('LibClose')
    $kindBox.Style = $Window.Resources['DarkCombo']
    foreach ($button in $import,$rename,$delete) { $button.Style = $Window.Resources['Ghost'] }
    $close.Style = $Window.Resources['PrimarySm']
    [void]$kindBox.Items.Add('Soundpacks')
    [void]$kindBox.Items.Add('ReShade looks')
    $kindBox.SelectedIndex = 0

    $getKind = { if ($kindBox.SelectedIndex -eq 0) { 'Soundpack' } else { 'ReShade' } }
    $refreshDialog = {
        $kind = & $getKind
        $list.Items.Clear()
        foreach ($item in @(Get-LibraryItems $kind)) { [void]$list.Items.Add($item) }
        $dropText.Text = if ($kind -eq 'Soundpack') { 'Drop a soundpack folder here, or use Import folder' } else { 'Drop a ReShade look folder here, or use Import folder' }
        $status.Text = if ($list.Items.Count -eq 0) { 'This library is empty.' } else { "$($list.Items.Count) item(s). File counts and profile usage are shown above." }
    }
    $importPaths = {
        param([string[]]$Paths)
        $kind = & $getKind
        $done = 0
        $lastError = ''
        foreach ($path in $Paths) {
            if (-not (Test-Path $path -PathType Container)) { $lastError = 'Drop folders rather than individual files.'; continue }
            try {
                if (-not (Confirm-LibraryImport $manager $kind $path)) { continue }
                [void](Import-LibraryFolder $kind $path)
                $done++
            }
            catch { $lastError = $_.Exception.Message }
        }
        & $refreshDialog
        if ($done -gt 0) { $status.Text = "Imported $done folder(s)." }
        elseif ($lastError) { $status.Text = $lastError }
    }
    $kindBox.Add_SelectionChanged({ & $refreshDialog })
    $drop.Add_DragOver({ param($s,$e) $e.Effects = if ($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { [Windows.DragDropEffects]::Copy } else { [Windows.DragDropEffects]::None }; $e.Handled = $true })
    $drop.Add_Drop({ param($s,$e) $paths = @($e.Data.GetData([Windows.DataFormats]::FileDrop)); & $importPaths $paths })
    $import.Add_Click({
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = 'Choose a pack folder to import'
        $picker.ShowNewFolderButton = $false
        if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { & $importPaths @($picker.SelectedPath) }
        $picker.Dispose()
    })
    $rename.Add_Click({
        $selected = $list.SelectedItem
        if (-not $selected) { $status.Text = 'Select a pack to rename.'; return }
        $kind = & $getKind
        $newName = Show-NamePrompt $manager 'Rename pack' 'Choose a new library name.' ([string]$selected.Name)
        if (-not $newName -or $newName -eq [string]$selected.Name) { return }
        try { Rename-LibraryItem $kind ([string]$selected.Name) $newName; & $refreshDialog; $status.Text = "Renamed to $newName and updated every dependent profile." }
        catch { $status.Text = $_.Exception.Message }
    })
    $delete.Add_Click({
        $selected = $list.SelectedItem
        if (-not $selected) { $status.Text = 'Select a pack to delete.'; return }
        $kind = & $getKind
        $used = @($selected.UsedBy)
        $warning = if ($used.Count -gt 0) {
            "`n`nUsed by: $($used -join ', ')`nThose profiles will be reset to the safe default."
        } else { '' }
        $answer = [Windows.MessageBox]::Show($manager, "Delete '$($selected.Name)'?$warning", 'Xn Fresh Deploy', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        try {
            $root = Get-LibraryRoot $kind
            $path = Get-SafeChildPath $root ([string]$selected.Name)
            Remove-Item -LiteralPath $path -Recurse -Force
            $property = if ($kind -eq 'Soundpack') { 'soundpack' } else { 'reshade' }
            $fallback = if ($kind -eq 'Soundpack') { 'None' } else { 'Keep current' }
            foreach ($server in $script:Servers) { if ([string]$server.$property -eq [string]$selected.Name) { Set-Prop $server $property $fallback } }
            Save-Servers
            & $refreshDialog
            $status.Text = "Deleted $($selected.Name)."
        }
        catch { $status.Text = $_.Exception.Message }
    })
    $close.Add_Click({ $manager.DialogResult = $true })
    & $refreshDialog
    [void]$manager.ShowDialog()
    Refresh-Libraries
    Rebuild-ServerRows
}

function Show-ReShadeManager {
    $managerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ReShade manager" Width="900" Height="720" MinWidth="820" MinHeight="650"
        WindowStartupLocation="CenterOwner" Background="#0B0F17" Foreground="#E6EDF3" FontFamily="Segoe UI">
  <Grid Margin="22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid Grid.Row="0" Margin="0,0,0,15">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="RESHADE MANAGER" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold"/>
        <TextBlock Text="FiveM graphics, kept healthy" FontSize="22" FontWeight="SemiBold" Margin="0,3,0,0"/>
        <TextBlock Text="Verified installs, shader packs, preset checks, safe repair, and precise removal." Foreground="#8B949E" FontSize="11.5" Margin="0,4,0,0"/>
      </StackPanel>
      <Button x:Name="RsRefresh" Grid.Column="1" Content="Check now" VerticalAlignment="Center"/>
    </Grid>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="360"/></Grid.ColumnDefinitions>
      <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <Border Background="#111722" BorderBrush="#263149" BorderThickness="1" CornerRadius="12" Padding="16" Margin="0,0,0,12">
            <StackPanel>
              <TextBlock Text="INSTALL HEALTH" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold"/>
              <TextBlock x:Name="RsStatus" Text="Checking..." FontSize="18" FontWeight="SemiBold" Margin="0,4,0,10"/>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                <TextBlock Text="Installed" Foreground="#8B949E" Margin="0,3"/><TextBlock x:Name="RsInstalled" Grid.Column="1" Margin="0,3"/>
                <TextBlock Grid.Row="1" Text="Latest official" Foreground="#8B949E" Margin="0,3"/><TextBlock x:Name="RsLatest" Grid.Row="1" Grid.Column="1" Margin="0,3"/>
                <TextBlock Grid.Row="2" Text="DLL mode" Foreground="#8B949E" Margin="0,3"/><TextBlock x:Name="RsDll" Grid.Row="2" Grid.Column="1" Margin="0,3"/>
                <TextBlock Grid.Row="3" Text="Library" Foreground="#8B949E" Margin="0,3"/><TextBlock x:Name="RsCounts" Grid.Row="3" Grid.Column="1" Margin="0,3"/>
              </Grid>
              <TextBlock x:Name="RsIssues" Foreground="#AAB7D7" FontSize="11.5" TextWrapping="Wrap" Margin="0,11,0,0"/>
            </StackPanel>
          </Border>
          <Border Background="#111722" BorderBrush="#263149" BorderThickness="1" CornerRadius="12" Padding="16">
            <StackPanel>
              <TextBlock Text="PRESET COMPATIBILITY" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold"/>
              <TextBlock x:Name="RsCompat" Foreground="#AAB7D7" FontSize="11.5" TextWrapping="Wrap" Margin="0,8,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <Border Background="#111722" BorderBrush="#4859A6" BorderThickness="1" CornerRadius="12" Padding="16" Margin="0,0,0,12">
            <StackPanel>
              <TextBlock Text="SHADER PACKS" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold"/>
              <TextBlock Text="Choose what Install or Repair should include." Foreground="#8B949E" FontSize="11.5" Margin="0,4,0,9"/>
              <CheckBox x:Name="RsStandard" Content="Standard ReShade shaders" Foreground="#E6EDF3" Margin="0,4"/>
              <CheckBox x:Name="RsSweetFX" Content="SweetFX" Foreground="#E6EDF3" Margin="0,4"/>
              <CheckBox x:Name="RsQuint" Content="qUINT" Foreground="#E6EDF3" Margin="0,4"/>
              <CheckBox x:Name="RsProd80" Content="prod80" Foreground="#E6EDF3" Margin="0,4"/>
              <Button x:Name="RsCustom" Content="Choose custom shader folder" HorizontalAlignment="Left" Margin="0,10,0,0"/>
              <TextBlock x:Name="RsCustomText" Text="No custom folder selected" Foreground="#8B949E" FontSize="10.5" TextWrapping="Wrap" Margin="0,6,0,0"/>
              <TextBlock Text="DLL MODE" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold" Margin="0,14,0,5"/>
              <ComboBox x:Name="RsMode" Height="34"/>
              <Button x:Name="RsInstall" Content="Install latest" Margin="0,14,0,0"/>
              <Button x:Name="RsRepair" Content="Repair or reinstall" Margin="0,7,0,0"/>
              <Button x:Name="RsSwitch" Content="Switch DLL mode" Margin="0,7,0,0"/>
            </StackPanel>
          </Border>
          <Border Background="#111722" BorderBrush="#263149" BorderThickness="1" CornerRadius="12" Padding="16">
            <StackPanel>
              <TextBlock Text="FIVEM INTEGRATION" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold"/>
              <TextBlock Text="After FiveM shows its ReShade acknowledgement in F8, this finds and applies it automatically." Foreground="#8B949E" FontSize="11.5" TextWrapping="Wrap" Margin="0,4,0,9"/>
              <Button x:Name="RsAck" Content="Find and apply acknowledgement"/>
              <Button x:Name="RsUninstall" Content="Full managed uninstall" Margin="0,10,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>
    </Grid>

    <Border Grid.Row="2" Background="#111722" BorderBrush="#263149" BorderThickness="1" CornerRadius="9" Padding="12,9" Margin="0,14,0,0">
      <TextBlock x:Name="RsAction" Text="Ready." Foreground="#AAB7D7" FontSize="11.5" TextWrapping="Wrap"/>
    </Border>
    <Button x:Name="RsClose" Grid.Row="3" Content="Done" HorizontalAlignment="Right" Margin="0,14,0,0"/>
  </Grid>
</Window>
'@
    $manager = [Windows.Markup.XamlReader]::Parse($managerXaml)
    $manager.Owner = $script:Window
    $controls = @{}
    foreach ($name in 'RsRefresh','RsStatus','RsInstalled','RsLatest','RsDll','RsCounts','RsIssues','RsCompat','RsStandard','RsSweetFX','RsQuint','RsProd80','RsCustom','RsCustomText','RsMode','RsInstall','RsRepair','RsSwitch','RsAck','RsUninstall','RsAction','RsClose') {
        $controls[$name] = $manager.FindName($name)
    }
    foreach ($button in $controls.RsRefresh,$controls.RsCustom,$controls.RsRepair,$controls.RsSwitch,$controls.RsAck,$controls.RsUninstall) { $button.Style = $Window.Resources['Ghost'] }
    $controls.RsInstall.Style = $Window.Resources['Primary']
    $controls.RsClose.Style = $Window.Resources['PrimarySm']
    $controls.RsMode.Style = $Window.Resources['DarkCombo']
    [void]$controls.RsMode.Items.Add('dxgi.dll')
    [void]$controls.RsMode.Items.Add('d3d11.dll')
    $state = @{ Official = $null; CustomFolders = @(); Initialized = $false; Busy = $false }

    $setBusy = {
        param([bool]$Busy, [string]$Message)
        $state.Busy = $Busy
        foreach ($button in $controls.RsRefresh,$controls.RsCustom,$controls.RsInstall,$controls.RsRepair,$controls.RsSwitch,$controls.RsAck,$controls.RsUninstall) { $button.IsEnabled = -not $Busy }
        if ($Message) { $controls.RsAction.Text = $Message }
        Pump-MainUi
    }
    $getSelectedPacks = {
        $packs = @()
        if ($controls.RsStandard.IsChecked) { $packs += 'Standard' }
        if ($controls.RsSweetFX.IsChecked) { $packs += 'SweetFX' }
        if ($controls.RsQuint.IsChecked) { $packs += 'qUINT' }
        if ($controls.RsProd80.IsChecked) { $packs += 'prod80' }
        return $packs
    }
    $renderHealth = {
        param($Health)
        $controls.RsStatus.Text = $Health.Status
        $controls.RsStatus.Foreground = New-Brush (if ($Health.Ready) { '#54D6A3' } elseif ($Health.Status -eq 'Not installed') { '#8B949E' } else { '#FFC14D' })
        $controls.RsInstalled.Text = if ($Health.Version) { "ReShade $($Health.Version)" } else { 'Not detected' }
        $controls.RsDll.Text = $Health.DllMode
        $controls.RsCounts.Text = "$($Health.ShaderCount) shaders, $($Health.TextureCount) textures"
        $controls.RsIssues.Text = if ($Health.Issues.Count -eq 0) { 'No health problems found.' } else { @($Health.Issues | ForEach-Object { "- $_" }) -join "`r`n" }
        $compat = $Health.Compatibility
        $compatLines = @("Checked $($compat.PresetCount) preset(s).")
        if ($compat.MissingShaders.Count -gt 0) { $compatLines += "Missing shaders: $(@($compat.MissingShaders | Select-Object -First 12) -join ', ')" }
        if ($compat.MissingTextures.Count -gt 0) { $compatLines += "Missing textures: $(@($compat.MissingTextures | Select-Object -First 12) -join ', ')" }
        if ($compat.Ready) { $compatLines += 'Every detected preset reference is available.' }
        $controls.RsCompat.Text = $compatLines -join "`r`n"
        if (-not $state.Initialized) {
            $packs = if ($Health.Manifest) { @($Health.Manifest.shaderPacks) } else { @('Standard') }
            $controls.RsStandard.IsChecked = ($packs -contains 'Standard')
            $controls.RsSweetFX.IsChecked = ($packs -contains 'SweetFX')
            $controls.RsQuint.IsChecked = ($packs -contains 'qUINT')
            $controls.RsProd80.IsChecked = ($packs -contains 'prod80')
            $state.CustomFolders = if ($Health.Manifest) { @($Health.Manifest.customSources | Where-Object { $_ -and (Test-Path $_ -PathType Container) }) } else { @() }
            $mode = if ($Health.DllMode -in 'dxgi.dll','d3d11.dll') { $Health.DllMode } elseif ($Health.Manifest -and [string]$Health.Manifest.dllMode -in 'dxgi.dll','d3d11.dll') { [string]$Health.Manifest.dllMode } else { 'dxgi.dll' }
            $controls.RsMode.SelectedItem = $mode
            $state.Initialized = $true
        }
        $controls.RsCustomText.Text = if ($state.CustomFolders.Count) { @($state.CustomFolders | ForEach-Object { Split-Path $_ -Leaf }) -join ', ' } else { 'No custom folder selected' }
        return $Health
    }
    $refresh = {
        param([bool]$Online)
        & $setBusy $true (if ($Online) { 'Checking the local install and the official ReShade release...' } else { 'Checking the local ReShade install...' })
        try {
            $health = Get-ReShadeHealth
            [void](& $renderHealth $health)
            if ($Online) { $state.Official = Get-ReShadeOfficialInfo }
            if ($state.Official) {
                $update = $false
                try { if ($health.Version) { $update = ([version]$health.Version -lt [version]$state.Official.Version) } } catch {}
                $controls.RsLatest.Text = "ReShade $($state.Official.Version)" + $(if ($update) { ' - update available' } else { ' - current' })
                $controls.RsInstall.Content = if ($health.Version) { $(if ($update) { 'Update to latest' } else { 'Reinstall latest' }) } else { 'Install latest' }
                if ($update) {
                    $controls.RsLatest.Foreground = New-Brush '#FFC14D'
                    $script:BtnReshadeManager.Content = 'Open ReShade manager - update available'
                    $controls.RsAction.Text = "ReShade $($state.Official.Version) is available. Install uses the publisher thumbprint shown on reshade.me."
                }
                else {
                    $controls.RsLatest.Foreground = New-Brush '#54D6A3'
                    $script:BtnReshadeManager.Content = 'Open ReShade manager'
                    $controls.RsAction.Text = 'Health check complete.'
                }
            }
            else { $controls.RsLatest.Text = 'Press Check now'; $controls.RsAction.Text = 'Local health check complete.' }
        }
        catch { $controls.RsLatest.Text = 'Online check unavailable'; $controls.RsAction.Text = $_.Exception.Message }
        finally { & $setBusy $false '' }
    }
    $runInstall = {
        param([string]$Action)
        if ($state.Busy) { return }
        $mode = [string]$controls.RsMode.SelectedItem
        $packs = @(& $getSelectedPacks)
        $existing = Get-ReShadeBaseManifest
        if ($Action -eq 'Install' -and $existing) {
            if ([Windows.MessageBox]::Show($manager, 'Reinstall or update the managed ReShade files now? Your preset profiles stay untouched.', 'ReShade manager', 'YesNo', 'Question') -ne 'Yes') { return }
        }
        & $setBusy $true 'Building and verifying the new ReShade setup...'
        try {
            [void](Install-ReShadeManaged $packs $mode @($state.CustomFolders))
            $controls.RsAction.Text = 'ReShade was installed and every copied file passed verification.'
            [void](& $renderHealth (Get-ReShadeHealth))
        }
        catch { $controls.RsAction.Text = $_.Exception.Message }
        finally { & $setBusy $false '' }
    }

    $controls.RsRefresh.Add_Click({ & $refresh $true })
    $controls.RsInstall.Add_Click({ & $runInstall 'Install' })
    $controls.RsRepair.Add_Click({ & $runInstall 'Repair' })
    $controls.RsSwitch.Add_Click({
        if ($state.Busy) { return }
        & $setBusy $true 'Switching the ReShade DLL mode with a rollback copy...'
        try { [void](Set-ReShadeDllMode ([string]$controls.RsMode.SelectedItem)); $controls.RsAction.Text = "ReShade now uses $($controls.RsMode.SelectedItem)."; [void](& $renderHealth (Get-ReShadeHealth)) }
        catch { $controls.RsAction.Text = $_.Exception.Message }
        finally { & $setBusy $false '' }
    })
    $controls.RsCustom.Add_Click({
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = 'Choose a custom ReShade shader folder'
        $picker.ShowNewFolderButton = $false
        try {
            if ($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Confirm-LibraryImport $manager 'ReShade' $picker.SelectedPath)) {
                $state.CustomFolders = @(@($state.CustomFolders) + $picker.SelectedPath | Select-Object -Unique)
                $controls.RsCustomText.Text = @($state.CustomFolders | ForEach-Object { Split-Path $_ -Leaf }) -join ', '
                $controls.RsAction.Text = 'Custom shaders selected. Press Install or Repair to add only their shader and texture files.'
            }
        }
        finally { $picker.Dispose() }
    })
    $controls.RsAck.Add_Click({
        if ($state.Busy) { return }
        & $setBusy $true 'Searching recent FiveM logs for the ReShade acknowledgement...'
        try {
            $ack = Get-FiveMReShadeAcknowledgement
            if (-not $ack) { throw 'No acknowledgement was found yet. Start FiveM once, open F8, let the ReShade line appear, close FiveM, then try again.' }
            $path = Set-FiveMReShadeAcknowledgement $ack
            $controls.RsAction.Text = "Acknowledgement applied safely to $path. The previous file was backed up."
        }
        catch { $controls.RsAction.Text = $_.Exception.Message }
        finally { & $setBusy $false '' }
    })
    $controls.RsUninstall.Add_Click({
        $manifest = Get-ReShadeBaseManifest
        if (-not $manifest) { $controls.RsAction.Text = 'There is no managed ReShade install to remove.'; return }
        $count = @($manifest.files).Count
        if ([Windows.MessageBox]::Show($manager, "Remove the $count files recorded by the ReShade manager?`n`nOriginal files that were replaced will be restored. Preset profiles are not deleted.", 'ReShade manager', 'YesNo', 'Warning') -ne 'Yes') { return }
        & $setBusy $true 'Removing only the files recorded in the managed-install manifest...'
        try { $removed = Uninstall-ReShadeManaged; $controls.RsAction.Text = "Managed ReShade was removed ($removed recorded files). Original files were restored where needed."; $state.Initialized = $false; [void](& $renderHealth (Get-ReShadeHealth)) }
        catch { $controls.RsAction.Text = $_.Exception.Message }
        finally { & $setBusy $false '' }
    })
    $controls.RsClose.Add_Click({ $manager.DialogResult = $true })
    $manager.Add_ContentRendered({ if (-not $state.ContainsKey('FirstCheck')) { $state.FirstCheck = $true; & $refresh $true } })
    [void]$manager.ShowDialog()
}

function Get-UniqueServerName([string]$BaseName) {
    $candidate = $BaseName.Trim()
    if (-not $candidate) { $candidate = 'Imported server' }
    if ($candidate.Length -gt 30) { $candidate = $candidate.Substring(0, 30).Trim() }
    if (-not (Get-ServerByName $candidate)) { return $candidate }
    for ($i = 2; $i -le 999; $i++) {
        $suffix = " $i"
        $maxBase = [Math]::Max(1, 30 - $suffix.Length)
        $stem = if ($candidate.Length -gt $maxBase) { $candidate.Substring(0, $maxBase).Trim() } else { $candidate }
        $try = "$stem$suffix"
        if (-not (Get-ServerByName $try)) { return $try }
    }
    throw 'Could not create a unique server name.'
}

function Get-ServerProfileBundle {
    $clean = @()
    foreach ($server in $script:Servers) {
        $clean += [ordered]@{
            name = [string]$server.name
            connect = [string]$server.connect
            soundpack = [string]$server.soundpack
            reshade = [string]$server.reshade
            commands = @(Get-ProfileCommands $server | ForEach-Object { [ordered]@{ name = [string]$_.name; value = [string]$_.value } })
            lastPlayed = if ($server.lastPlayed) { [string]$server.lastPlayed } else { $null }
            favorite = [bool]$server.favorite
        }
    }
    $bundle = [ordered]@{
        format = 'XnFreshDeployProfiles'
        version = 1
        exportedAt = [DateTime]::UtcNow.ToString('o')
        servers = $clean
        library = [ordered]@{
            soundpacks = @($script:SoundOptions | Where-Object { $_ -ne 'None' })
            reshade = @($script:ReshadeOptions | Where-Object { $_ -ne 'Keep current' })
        }
    }
    return $bundle
}

function Get-UniqueLibraryName([string]$Kind, [string]$BaseName) {
    $root = Get-LibraryRoot $Kind
    $candidate = $BaseName.Trim()
    if ($candidate.Length -gt 30) { $candidate = $candidate.Substring(0, 30).Trim() }
    if (-not (Test-Path (Get-SafeChildPath $root $candidate))) { return $candidate }
    for ($i = 2; $i -le 999; $i++) {
        $suffix = " $i"
        $maxBase = [Math]::Max(1, 30 - $suffix.Length)
        $stem = if ($candidate.Length -gt $maxBase) { $candidate.Substring(0, $maxBase).Trim() } else { $candidate }
        $try = "$stem$suffix"
        if (-not (Test-Path (Get-SafeChildPath $root $try))) { return $try }
    }
    throw "Could not create a unique $Kind library name."
}

function New-PortableFileManifest([string]$Root) {
    $files = @(Get-TreeHashManifest $Root @('portable-manifest.json') $false $false)
    return [ordered]@{
        version = 1
        generatedAt = [DateTime]::UtcNow.ToString('o')
        files = @($files | ForEach-Object { [ordered]@{ path = $_.Path; length = $_.Length; sha256 = $_.SHA256 } })
    }
}

function Assert-PortableFileManifest([string]$Root) {
    $path = Join-Path $Root 'portable-manifest.json'
    if (-not (Test-Path $path -PathType Leaf)) { throw 'The portable backup has no integrity manifest.' }
    $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ([int]$saved.version -ne 1) { throw 'The portable-backup manifest version is not supported.' }
    $expected = @($saved.files)
    $actual = @(Get-TreeHashManifest $Root @('portable-manifest.json') $false $false)
    if ($expected.Count -ne $actual.Count) { throw 'Portable-backup verification found missing or unexpected files.' }
    $actualByPath = @{}
    foreach ($entry in $actual) { $actualByPath[$entry.Path] = $entry }
    foreach ($entry in $expected) {
        $relative = [string]$entry.path
        [void](Get-SafeChildPath $Root $relative)
        $found = $actualByPath[$relative]
        if (-not $found -or [int64]$entry.length -ne $found.Length -or [string]$entry.sha256 -ine $found.SHA256) {
            throw "Portable-backup verification failed for $relative."
        }
    }
}

function Export-PortableProfiles {
    $picker = New-Object Microsoft.Win32.SaveFileDialog
    $picker.Title = 'Create a full portable Xn Fresh Deploy backup'
    $picker.Filter = 'Xn portable backup (*.xnportable.zip)|*.xnportable.zip|ZIP files (*.zip)|*.zip'
    $picker.FileName = "Xn-Portable-$([DateTime]::Now.ToString('yyyy-MM-dd')).xnportable.zip"
    if (-not $picker.ShowDialog($script:Window)) { return $null }

    $stage = Join-Path $env:TEMP ("XnPortable-" + [Guid]::NewGuid().ToString('N'))
    $zipStage = $picker.FileName + '.partial-' + [Guid]::NewGuid().ToString('N')
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Get-ServerProfileBundle | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $stage 'profiles.json') -Encoding UTF8
        $usedSounds = @($script:Servers | ForEach-Object { [string]$_.soundpack } |
                        Where-Object { $_ -and $_ -ne 'None' -and (Test-LibraryName $_) } | Select-Object -Unique)
        $usedLooks = @($script:Servers | ForEach-Object { [string]$_.reshade } |
                       Where-Object { $_ -and $_ -ne 'Keep current' -and (Test-LibraryName $_) } | Select-Object -Unique)
        foreach ($name in $usedSounds) {
            $source = Get-SafeChildPath $script:SoundLibDir $name
            if (-not (Test-Path $source -PathType Container)) { throw "Full backup stopped because soundpack '$name' is missing." }
            $destination = Join-Path $stage "Library\Soundpacks\$name"
            Copy-DirectoryContents $source $destination (Get-LibraryExclusions 'Soundpack')
            Assert-TreesMatch $source $destination (Get-LibraryExclusions 'Soundpack')
        }
        foreach ($name in $usedLooks) {
            $source = Get-SafeChildPath $script:ReshadeLibDir $name
            if (-not (Test-Path $source -PathType Container)) { throw "Full backup stopped because ReShade look '$name' is missing." }
            $destination = Join-Path $stage "Library\ReShade\$name"
            Copy-DirectoryContents $source $destination (Get-LibraryExclusions 'ReShade')
            Assert-TreesMatch $source $destination (Get-LibraryExclusions 'ReShade')
        }
        New-PortableFileManifest $stage | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $stage 'portable-manifest.json') -Encoding UTF8
        [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipStage, [IO.Compression.CompressionLevel]::Optimal, $false)
        $archive = [IO.Compression.ZipFile]::OpenRead($zipStage)
        try {
            if (-not ($archive.Entries | Where-Object { $_.FullName -eq 'profiles.json' }) -or
                -not ($archive.Entries | Where-Object { $_.FullName -eq 'portable-manifest.json' })) { throw 'The portable ZIP did not close correctly.' }
        }
        finally { $archive.Dispose() }
        Move-Item -LiteralPath $zipStage -Destination $picker.FileName -Force
        return $picker.FileName
    }
    finally {
        if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $zipStage) { Remove-Item -LiteralPath $zipStage -Force -ErrorAction SilentlyContinue }
    }
}

function Import-PortableProfilesFromPath([string]$Path) {
    if (-not (Test-Path $Path -PathType Leaf)) { throw 'Choose a portable backup file.' }
    $stage = Join-Path $env:TEMP ("XnPortableImport-" + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $archive = [IO.Compression.ZipFile]::OpenRead($Path)
        try {
            if ($archive.Entries.Count -gt 100000) { throw 'The portable backup contains too many files.' }
            [int64]$expandedBytes = 0
            foreach ($entry in $archive.Entries) {
                $relative = $entry.FullName.Replace('/', '\')
                if ([IO.Path]::IsPathRooted($relative) -or @($relative -split '\\') -contains '..') { throw 'The portable backup contains an unsafe file path.' }
                if ($relative.TrimEnd('\')) { [void](Get-SafeChildPath $stage $relative.TrimEnd('\')) }
                $expandedBytes += $entry.Length
                if ($expandedBytes -gt 100GB) { throw 'The portable backup is unexpectedly large.' }
            }
        }
        finally { $archive.Dispose() }
        [IO.Compression.ZipFile]::ExtractToDirectory($Path, $stage)
        Assert-PortableFileManifest $stage
        $profilesPath = Join-Path $stage 'profiles.json'
        $bundle = Get-Content -LiteralPath $profilesPath -Raw | ConvertFrom-Json
        if ([string]$bundle.format -ne 'XnFreshDeployProfiles' -or [int]$bundle.version -ne 1) { throw 'The portable backup contains an unsupported profile file.' }
        if (@($bundle.servers).Count -gt 500) { throw 'The portable backup contains too many profiles.' }

        $soundFolders = @(Get-ChildItem (Join-Path $stage 'Library\Soundpacks') -Directory -ErrorAction SilentlyContinue)
        $lookFolders = @(Get-ChildItem (Join-Path $stage 'Library\ReShade') -Directory -ErrorAction SilentlyContinue)
        $allPackFiles = @($soundFolders + $lookFolders | ForEach-Object { Get-ChildItem $_.FullName -Recurse -Force -File })
        $riskyExtensions = @('.exe','.msi','.com','.scr','.bat','.cmd','.ps1','.psm1','.vbs','.vbe','.js','.jse','.wsf','.wsh','.dll','.asi')
        $risky = @($allPackFiles | Where-Object { $riskyExtensions -contains $_.Extension.ToLowerInvariant() } | Select-Object -First 12)
        $typeGroups = @($allPackFiles | Group-Object { if ($_.Extension) { $_.Extension.ToLowerInvariant() } else { '[no extension]' } } |
                        Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Ascending = $true })
        $types = if ($typeGroups.Count) { @($typeGroups | Select-Object -First 12 | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ' } else { 'none' }
        $message = "Import this full backup?`n`n$(@($bundle.servers).Count) profiles`n$($soundFolders.Count) soundpacks`n$($lookFolders.Count) ReShade looks`n$($allPackFiles.Count) pack files`n`nFile types: $types"
        $icon = 'Question'
        if ($risky.Count -gt 0) {
            $message += "`n`nWarning: executable, script, or DLL files are included:`n$(@($risky | ForEach-Object { $_.Name }) -join "`n")`n`nOnly continue if you trust this backup."
            $icon = 'Warning'
        }
        if ([Windows.MessageBox]::Show($script:Window, $message, 'Portable backup preview', 'YesNo', $icon) -ne 'Yes') { return $null }

        $soundMap = @{}
        $lookMap = @{}
        foreach ($definition in @(
            [pscustomobject]@{ Kind = 'Soundpack'; Folders = $soundFolders; Map = $soundMap },
            [pscustomobject]@{ Kind = 'ReShade'; Folders = $lookFolders; Map = $lookMap }
        )) {
            foreach ($folder in $definition.Folders) {
                if (-not (Test-LibraryName $folder.Name)) { throw "The backup contains an unsafe library name: $($folder.Name)" }
                $name = $folder.Name
                $root = Get-LibraryRoot $definition.Kind
                $destination = Get-SafeChildPath $root $name
                if (Test-Path $destination -PathType Container) {
                    $same = $true
                    try { Assert-TreesMatch $folder.FullName $destination (Get-LibraryExclusions $definition.Kind) }
                    catch { $same = $false }
                    if (-not $same) { $name = Get-UniqueLibraryName $definition.Kind "$name Imported" }
                }
                if (-not (Test-Path (Get-SafeChildPath $root $name))) { [void](Import-LibraryFolder $definition.Kind $folder.FullName $name) }
                $definition.Map[$folder.Name] = $name
            }
        }

        foreach ($server in @($bundle.servers)) {
            $sound = [string]$server.soundpack
            $look = [string]$server.reshade
            if ($soundMap.ContainsKey($sound)) { $server.soundpack = [string]$soundMap[$sound] }
            if ($lookMap.ContainsKey($look)) { $server.reshade = [string]$lookMap[$look] }
        }
        $importPath = Join-Path $stage 'profiles-import.json'
        $bundle | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $importPath -Encoding UTF8
        Refresh-Libraries
        $result = Import-ServerProfilesFromPath $importPath
        return [pscustomobject]@{ Added = $result.Added; Skipped = $result.Skipped; MissingAssignments = $result.MissingAssignments; Soundpacks = $soundFolders.Count; ReShadeLooks = $lookFolders.Count }
    }
    finally { if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Export-ServerProfiles {
    $picker = New-Object Microsoft.Win32.SaveFileDialog
    $picker.Title = 'Export Xn Fresh Deploy profiles'
    $picker.Filter = 'Xn profile backup (*.xnprofiles.json)|*.xnprofiles.json|JSON files (*.json)|*.json'
    $picker.FileName = "Xn-Profiles-$([DateTime]::Now.ToString('yyyy-MM-dd')).xnprofiles.json"
    if (-not $picker.ShowDialog($script:Window)) { return $null }
    Get-ServerProfileBundle | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $picker.FileName -Encoding UTF8
    return $picker.FileName
}

function Import-ServerProfilesFromPath([string]$Path) {
    $bundle = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$bundle.format -ne 'XnFreshDeployProfiles' -or [int]$bundle.version -ne 1) {
        throw 'That file is not a supported Xn Fresh Deploy profile backup.'
    }
    $incoming = @($bundle.servers)
    if ($incoming.Count -gt 500) { throw 'The backup contains too many profiles.' }
    $added = 0
    $skipped = 0
    $missingAssignments = 0
    foreach ($item in $incoming) {
        $rawName = [string]$item.name
        $connect = Normalize-ConnectTarget ([string]$item.connect)
        if ($rawName -notmatch '^[\w \-\.]{1,30}$' -or -not $connect) { $skipped++; continue }
        $name = Get-UniqueServerName $rawName
        $sound = if ($item.soundpack) { [string]$item.soundpack } else { 'None' }
        $reshade = if ($item.reshade) { [string]$item.reshade } else { 'Keep current' }
        if ($sound -ne 'None') {
            if (-not (Test-LibraryName $sound)) { $sound = 'None'; $missingAssignments++ }
            elseif ($script:SoundOptions -notcontains $sound) { $missingAssignments++ }
        }
        if ($reshade -ne 'Keep current') {
            if (-not (Test-LibraryName $reshade)) { $reshade = 'Keep current'; $missingAssignments++ }
            elseif ($script:ReshadeOptions -notcontains $reshade) { $missingAssignments++ }
        }
        $server = [pscustomobject]@{
            name = $name
            connect = $connect
            soundpack = $sound
            reshade = $reshade
            commands = @(Normalize-ProfileCommands $item.commands)
            lastPlayed = if ($item.lastPlayed) { [string]$item.lastPlayed } else { $null }
            favorite = [bool]$item.favorite
        }
        $script:Servers = @($script:Servers) + $server
        $added++
    }
    if ($added -gt 0) { Save-Servers; Rebuild-ServerRows }
    return [pscustomobject]@{ Added = $added; Skipped = $skipped; MissingAssignments = $missingAssignments }
}

function Import-ServerProfiles {
    $picker = New-Object Microsoft.Win32.OpenFileDialog
    $picker.Title = 'Import Xn Fresh Deploy profiles'
    $picker.Filter = 'Xn backups (*.xnprofiles.json;*.xnportable.zip;*.json;*.zip)|*.xnprofiles.json;*.xnportable.zip;*.json;*.zip|All files (*.*)|*.*'
    if (-not $picker.ShowDialog($script:Window)) { return $null }
    if ([IO.Path]::GetExtension($picker.FileName) -ieq '.zip') { return Import-PortableProfilesFromPath $picker.FileName }
    return Import-ServerProfilesFromPath $picker.FileName
}

function Format-LastPlayed($Value) {
    if (-not $Value) { return 'Never played from Fresh Deploy' }
    try {
        $when = [DateTime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
        $today = [DateTime]::Today
        if ($when.Date -eq $today) { return "Last played today at $($when.ToString('HH:mm'))" }
        if ($when.Date -eq $today.AddDays(-1)) { return "Last played yesterday at $($when.ToString('HH:mm'))" }
        return "Last played $($when.ToString('dd MMM yyyy'))"
    }
    catch { return 'Last played date unavailable' }
}

$script:ServerStatus = @{}
$script:ProfileBadges = @{}
$script:StatusChecks = @()
$script:StatusPool = $null
$script:StatusTimer = $null

$ServerProbeScript = {
    param([string]$Connect)
    $target = $Connect.Trim().Trim('"').Trim("'") -replace '^fivem://connect/', ''
    $target = $target.TrimEnd('/')
    if ($target -match '^(?:https?://)?(?:www\.)?cfx\.re/join/([a-zA-Z0-9]{4,12})$') { $target = $Matches[1] }
    if ($target -match '^[a-zA-Z0-9]{4,12}$') {
        try {
            $response = Invoke-RestMethod -Uri "https://servers-frontend.fivem.net/api/servers/single/$target" -TimeoutSec 6 -UseBasicParsing -ErrorAction Stop
            if (-not $response.Data) { throw 'Not listed by Cfx.re.' }
            return [pscustomobject]@{ Online = $true; Detail = 'Online' }
        }
        catch { return [pscustomobject]@{ Online = $false; Detail = 'Server offline' } }
    }
    $endpoint = $target
    if ($endpoint -notmatch ':\d+$' -and $endpoint -notmatch '/') { $endpoint = "$endpoint`:30120" }
    $baseUri = if ($endpoint -match '^https?://') { $endpoint.TrimEnd('/') } else { "http://$($endpoint.TrimEnd('/'))" }
    try {
        $info = Invoke-RestMethod -Uri "$baseUri/info.json" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if (-not ($info.vars -or $info.resources -or $info.server)) { throw 'Not a FiveM endpoint.' }
        return [pscustomobject]@{ Online = $true; Detail = 'Online' }
    }
    catch { return [pscustomobject]@{ Online = $false; Detail = 'Server offline' } }
}

function Update-ProfileReadiness([string]$Name) {
    $badge = $script:ProfileBadges[$Name]
    $server = Get-ServerByName $Name
    if (-not $badge -or -not $server) { return }
    $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
    $text = 'Checking server...'; $colour = '#8FA4FF'
    if (-not (Test-Path $appDir -PathType Container)) { $text = 'FiveM missing'; $colour = '#FF8A96' }
    elseif (Test-FiveMRunning) { $text = 'FiveM running'; $colour = '#FFC14D' }
    elseif ([string]$server.soundpack -ne 'None' -and $script:SoundOptions -notcontains [string]$server.soundpack) { $text = 'Pack missing'; $colour = '#FF8A96' }
    elseif ([string]$server.reshade -ne 'Keep current' -and $script:ReshadeOptions -notcontains [string]$server.reshade) { $text = 'ReShade missing'; $colour = '#FF8A96' }
    elseif ([string]$server.reshade -ne 'Keep current' -and
            -not ((Test-Path (Join-Path $appDir 'plugins\dxgi.dll') -PathType Leaf) -or (Test-Path (Join-Path $appDir 'plugins\d3d11.dll') -PathType Leaf))) {
        $text = 'ReShade base missing'; $colour = '#FF8A96'
    }
    else {
        $entry = $script:ServerStatus[$Name]
        if ($entry) {
            if ([bool]$entry.Online) { $text = 'Ready'; $colour = '#54D6A3' }
            else { $text = 'Server offline'; $colour = '#FF8A96' }
        }
    }
    $badge.Text = $text
    $badge.Foreground = New-Brush $colour
}

function Stop-ProfileStatusChecks {
    if ($script:StatusTimer) { $script:StatusTimer.Stop(); $script:StatusTimer = $null }
    foreach ($check in @($script:StatusChecks)) {
        try { if (-not $check.Handle.IsCompleted) { $check.PowerShell.Stop() } } catch {}
        try { $check.PowerShell.Dispose() } catch {}
    }
    $script:StatusChecks = @()
    if ($script:StatusPool) {
        try { $script:StatusPool.Close(); $script:StatusPool.Dispose() } catch {}
        $script:StatusPool = $null
    }
}

function Start-ProfileStatusChecks($Profiles) {
    Stop-ProfileStatusChecks
    $pending = @()
    foreach ($server in @($Profiles | Select-Object -First 100)) {
        $name = [string]$server.name
        $cached = $script:ServerStatus[$name]
        if ($cached -and ([DateTime]::UtcNow - [DateTime]$cached.CheckedAt).TotalSeconds -lt 60) { Update-ProfileReadiness $name; continue }
        $pending += $server
    }
    if ($pending.Count -eq 0) { return }
    $script:StatusPool = [RunspaceFactory]::CreateRunspacePool(1, 4)
    $script:StatusPool.Open()
    foreach ($server in $pending) {
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $script:StatusPool
        [void]$ps.AddScript($ServerProbeScript).AddArgument([string]$server.connect)
        $script:StatusChecks += [pscustomobject]@{ Name = [string]$server.name; PowerShell = $ps; Handle = $ps.BeginInvoke() }
    }
    $script:StatusTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:StatusTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:StatusTimer.Add_Tick({
        foreach ($check in @($script:StatusChecks)) {
            if (-not $check.Handle.IsCompleted) { continue }
            try {
                $output = @($check.PowerShell.EndInvoke($check.Handle))
                $result = if ($output.Count) { $output[-1] } else { [pscustomobject]@{ Online = $false; Detail = 'Server offline' } }
                $script:ServerStatus[$check.Name] = [pscustomobject]@{ Online = [bool]$result.Online; Detail = [string]$result.Detail; CheckedAt = [DateTime]::UtcNow }
            }
            catch { $script:ServerStatus[$check.Name] = [pscustomobject]@{ Online = $false; Detail = 'Server offline'; CheckedAt = [DateTime]::UtcNow } }
            finally { try { $check.PowerShell.Dispose() } catch {} }
            $script:StatusChecks = @($script:StatusChecks | Where-Object { $_ -ne $check })
            Update-ProfileReadiness $check.Name
        }
        if ($script:StatusChecks.Count -eq 0) {
            $script:StatusTimer.Stop()
            if ($script:StatusPool) { try { $script:StatusPool.Close(); $script:StatusPool.Dispose() } catch {}; $script:StatusPool = $null }
            if ([string]$script:CmbProfileSort.SelectedItem -eq 'Online status') { Rebuild-ServerRows }
        }
    })
    $script:StatusTimer.Start()
}

function Show-ProfileEditor($Server) {
    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Edit server profile" Width="650" Height="830" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" Background="#0B0F17" FontFamily="Segoe UI">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,18">
      <TextBlock Text="EDIT PROFILE" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold"/>
      <TextBlock Text="Update this server" Foreground="#E6EDF3" FontSize="21" FontWeight="SemiBold" Margin="0,3,0,0"/>
      <TextBlock Text="Change the address or its packs. Nothing is applied until you press Save changes."
                 Foreground="#8B949E" FontSize="11.5" TextWrapping="Wrap" Margin="0,4,0,0"/>
    </StackPanel>
    <StackPanel Grid.Row="1" Margin="0,0,0,12">
      <TextBlock Text="PROFILE NAME" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold" Margin="1,0,0,5"/>
      <TextBox x:Name="EditName" Height="36"/>
    </StackPanel>
    <StackPanel Grid.Row="2" Margin="0,0,0,12">
      <TextBlock Text="CONNECT CODE, LINK, OR IP" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold" Margin="1,0,0,5"/>
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBox x:Name="EditConnect" Height="36"/>
        <Button x:Name="EditTest" Grid.Column="2" Content="Test connection" Height="36"/>
      </Grid>
    </StackPanel>
    <Grid Grid.Row="3" Margin="0,0,0,14">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0">
        <TextBlock Text="SOUNDPACK" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold" Margin="1,0,0,5"/>
        <ComboBox x:Name="EditSound" Height="36"/>
      </StackPanel>
      <StackPanel Grid.Column="2">
        <TextBlock Text="RESHADE LOOK" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold" Margin="1,0,0,5"/>
        <ComboBox x:Name="EditReshade" Height="36"/>
      </StackPanel>
    </Grid>
    <StackPanel Grid.Row="4" Margin="0,0,0,12">
      <TextBlock Text="SERVER COMMANDS" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold" Margin="1,0,0,5"/>
      <ListBox x:Name="EditCommandList" Height="150" SelectionMode="Extended">
        <ListBox.ItemTemplate>
          <DataTemplate><TextBlock Text="{Binding Label}" TextWrapping="Wrap"/></DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>
      <TextBlock x:Name="EditCommandSummary" Text="Click one command. Hold Ctrl while clicking to choose several."
                 Foreground="#8B949E" FontSize="11" TextWrapping="Wrap" Margin="1,5,0,0"/>
      <Grid Margin="0,8,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <StackPanel x:Name="EditMouseScalePanel" Grid.Column="0" Visibility="Collapsed">
          <TextBlock Text="ON-FOOT MOUSE SCALE VALUE" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold" Margin="1,0,0,5"/>
          <TextBox x:Name="EditMouseScale" Height="34"/>
        </StackPanel>
        <StackPanel x:Name="EditFovPanel" Grid.Column="2" Visibility="Collapsed">
          <TextBlock Text="FIRST-PERSON FOV VALUE" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold" Margin="1,0,0,5"/>
          <TextBox x:Name="EditFov" Height="34"/>
          <TextBlock Text="Only works on servers that allow it." Foreground="#8B949E" FontSize="10.5" TextWrapping="Wrap" Margin="1,4,0,0"/>
        </StackPanel>
      </Grid>
      <Border Background="#111722" BorderBrush="#263149" BorderThickness="1" CornerRadius="9" Padding="10" Margin="0,9,0,0">
        <StackPanel>
          <TextBlock Text="ADD YOUR OWN COMMAND" Foreground="#8FA4FF" FontSize="10.5" FontWeight="SemiBold"/>
          <Grid Margin="0,6,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock Text="COMMAND NAME" Foreground="#8FA4FF" FontSize="10" FontWeight="SemiBold" Margin="1,0,0,4"/>
              <TextBox x:Name="EditCustomName" Height="34"/>
            </StackPanel>
            <StackPanel Grid.Column="2">
              <TextBlock Text="VALUE" Foreground="#8FA4FF" FontSize="10" FontWeight="SemiBold" Margin="1,0,0,4"/>
              <TextBox x:Name="EditCustomValue" Height="34"/>
            </StackPanel>
          </Grid>
          <DockPanel Margin="0,7,0,0" LastChildFill="True">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
              <Button x:Name="EditRemoveCustom" Content="Remove selected custom"/>
              <Button x:Name="EditAddCustom" Content="Add command" Margin="7,0,0,0"/>
            </StackPanel>
            <TextBlock x:Name="EditCustomStatus" Text="Enter a command name and value." Foreground="#8B949E" FontSize="10.5" TextWrapping="Wrap" VerticalAlignment="Center"/>
          </DockPanel>
        </StackPanel>
      </Border>
    </StackPanel>
    <Border Grid.Row="5" Background="#111722" BorderBrush="#263149" BorderThickness="1" CornerRadius="9" Padding="11,8">
      <TextBlock x:Name="EditStatus" Text="Ready to edit." Foreground="#8B949E" FontSize="11.5" TextWrapping="Wrap"/>
    </Border>
    <StackPanel Grid.Row="7" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="EditCancel" Content="Cancel" Margin="0,0,8,0"/>
      <Button x:Name="EditSave" Content="Save changes"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $dialog = [Windows.Markup.XamlReader]::Parse($dialogXaml)
    $dialog.Owner = $script:Window
    $nameBox = $dialog.FindName('EditName')
    $connectBox = $dialog.FindName('EditConnect')
    $soundBox = $dialog.FindName('EditSound')
    $reshadeBox = $dialog.FindName('EditReshade')
    $commandsList = $dialog.FindName('EditCommandList')
    $commandSummary = $dialog.FindName('EditCommandSummary')
    $mouseScalePanel = $dialog.FindName('EditMouseScalePanel')
    $mouseScaleBox = $dialog.FindName('EditMouseScale')
    $fovPanel = $dialog.FindName('EditFovPanel')
    $fovBox = $dialog.FindName('EditFov')
    $customNameBox = $dialog.FindName('EditCustomName')
    $customValueBox = $dialog.FindName('EditCustomValue')
    $addCustomButton = $dialog.FindName('EditAddCustom')
    $removeCustomButton = $dialog.FindName('EditRemoveCustom')
    $customStatus = $dialog.FindName('EditCustomStatus')
    $testButton = $dialog.FindName('EditTest')
    $status = $dialog.FindName('EditStatus')
    $cancel = $dialog.FindName('EditCancel')
    $save = $dialog.FindName('EditSave')

    $nameBox.Style = $Window.Resources['DarkText']
    $connectBox.Style = $Window.Resources['DarkText']
    $commandsList.Style = $Window.Resources['DarkList']
    $mouseScaleBox.Style = $Window.Resources['DarkText']
    $fovBox.Style = $Window.Resources['DarkText']
    $customNameBox.Style = $Window.Resources['DarkText']
    $customValueBox.Style = $Window.Resources['DarkText']
    $soundBox.Style = $Window.Resources['DarkCombo']
    $reshadeBox.Style = $Window.Resources['DarkCombo']
    $testButton.Style = $Window.Resources['Ghost']
    $addCustomButton.Style = $Window.Resources['Ghost']
    $removeCustomButton.Style = $Window.Resources['Ghost']
    $cancel.Style = $Window.Resources['Ghost']
    $save.Style = $Window.Resources['PrimarySm']

    $nameBox.Text = [string]$Server.name
    $connectBox.Text = [string]$Server.connect
    Initialize-ProfileCommandPicker $commandsList (Get-ProfileCommands $Server) $mouseScaleBox $fovBox
    Update-ProfileCommandPicker $commandsList $mouseScalePanel $fovPanel $commandSummary
    $commandsList.Add_SelectionChanged({
        param($s, $e)
        Update-ProfileCommandPicker $s $mouseScalePanel $fovPanel $commandSummary $e
    })
    $addCustomButton.Add_Click({
        try {
            $item = Add-CustomProfileCommandToPicker $commandsList $customNameBox $customValueBox
            Update-ProfileCommandPicker $commandsList $mouseScalePanel $fovPanel $commandSummary
            $customStatus.Text = "Added and selected: $($item.Name) $($item.Value)"
        }
        catch { $customStatus.Text = $_.Exception.Message }
    })
    $removeCustomButton.Add_Click({
        $removed = Remove-SelectedCustomProfileCommands $commandsList
        Update-ProfileCommandPicker $commandsList $mouseScalePanel $fovPanel $commandSummary
        $customStatus.Text = if ($removed -gt 0) { "Removed $removed custom command(s)." } else { 'Select a Custom entry first.' }
    })
    foreach ($option in $script:SoundOptions) { [void]$soundBox.Items.Add($option) }
    foreach ($option in $script:ReshadeOptions) { [void]$reshadeBox.Items.Add($option) }
    $soundBox.SelectedItem = if ($script:SoundOptions -contains [string]$Server.soundpack) { [string]$Server.soundpack } else { 'None' }
    $reshadeBox.SelectedItem = if ($script:ReshadeOptions -contains [string]$Server.reshade) { [string]$Server.reshade } else { 'Keep current' }

    $state = @{ Result = $null }
    $testButton.Add_Click({
        $testButton.IsEnabled = $false
        $status.Text = 'Testing the server...'
        $dialog.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        try {
            $result = Test-FiveMConnectTarget $connectBox.Text
            if ($result.Online) {
                $extra = if ($result.Players) { " $($result.Players)." } else { '' }
                $status.Foreground = New-Brush '#54D6A3'
                $status.Text = "Online.$extra $($result.Detail)"
                if (-not $nameBox.Text.Trim() -and $result.Name) { $nameBox.Text = ([string]$result.Name -replace '\^[0-9]', '') }
            } else {
                $status.Foreground = New-Brush '#FF8A96'
                $status.Text = $result.Detail
            }
        }
        finally { $testButton.IsEnabled = $true }
    })
    $cancel.Add_Click({ $dialog.DialogResult = $false })
    $save.Add_Click({
        $newName = $nameBox.Text.Trim()
        $newConnect = Normalize-ConnectTarget $connectBox.Text
        if ($newName -notmatch '^[\w \-\.]{1,30}$') { $status.Text = 'Use letters, numbers, spaces, dashes, or dots for the name (max 30).'; return }
        if (-not $newConnect) { $status.Text = 'Enter a connect code, link, or IP.'; return }
        $other = Get-ServerByName $newName
        if ($other -and [string]$other.name -ine [string]$Server.name) { $status.Text = "Another profile is already called '$newName'."; return }
        try { $commands = @(Get-ProfileCommandsFromPicker $commandsList $mouseScaleBox $fovBox) }
        catch { $status.Text = $_.Exception.Message; return }
        $state.Result = [pscustomobject]@{
            name = $newName
            connect = $newConnect
            soundpack = [string]$soundBox.SelectedItem
            reshade = [string]$reshadeBox.SelectedItem
            commands = $commands
        }
        $dialog.DialogResult = $true
    })
    [void]$dialog.ShowDialog()
    return $state.Result
}

function Rebuild-ServerRows {
    $script:UiLoading = $true
    $script:ServersPanel.Children.Clear()
    $script:ProfileBadges = @{}
    $query = $script:TxtProfileSearch.Text.Trim()
    $view = @($script:Servers)
    if ($query) {
        $view = @($view | Where-Object {
            ([string]$_.name).IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$_.connect).IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    }
    switch ([string]$script:CmbProfileSort.SelectedItem) {
        'Server name' { $view = @($view | Sort-Object { [string]$_.name }) }
        'Favourites'  { $view = @($view | Sort-Object @{ Expression = { [bool]$_.favorite }; Descending = $true }, @{ Expression = { [string]$_.name }; Ascending = $true }) }
        'Online status' {
            $view = @($view | Sort-Object @{ Expression = {
                $entry = if ($script:ServerStatus) { $script:ServerStatus[[string]$_.name] } else { $null }
                if ($entry -and $entry.Online) { 2 } elseif ($entry) { 0 } else { 1 }
            }; Descending = $true }, @{ Expression = { [string]$_.name }; Ascending = $true })
        }
        default {
            $view = @($view | Sort-Object @{ Expression = {
                try { [DateTime]::Parse([string]$_.lastPlayed).Ticks } catch { 0 }
            }; Descending = $true }, @{ Expression = { [string]$_.name }; Ascending = $true })
        }
    }
    $script:NoServersText.Visibility = if ($view.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    if ($script:Servers.Count -eq 0) {
        $script:NoServersTitle.Text = 'No server profiles yet'
        $script:NoServersHint.Text = 'Create one with the configurator on the right.'
    } else {
        $script:NoServersTitle.Text = 'No matching profiles'
        $script:NoServersHint.Text = 'Try another name, code, or sorting option.'
    }
    $script:TxtProfileSummary.Text = if ($query) { "$($view.Count) of $($script:Servers.Count)" } else { "$($script:Servers.Count) saved" }

    foreach ($srv in $view) {
        $card = New-Object System.Windows.Controls.Border
        $card.Background = New-Brush '#111722'
        $card.BorderBrush = New-Brush '#263149'
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(13)
        $card.Padding = New-Object System.Windows.Thickness(16)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

        $stack = New-Object System.Windows.Controls.StackPanel

        # Row 1: name, last played, and profile actions
        $top = New-Object System.Windows.Controls.DockPanel
        $top.LastChildFill = $true
        $topActions = New-Object System.Windows.Controls.StackPanel
        $topActions.Orientation = 'Horizontal'
        [System.Windows.Controls.DockPanel]::SetDock($topActions, 'Right')

        $btnFavourite = New-Object System.Windows.Controls.Button
        $btnFavourite.Content = if ([bool]$srv.favorite) { [string][char]0x2605 } else { [string][char]0x2606 }
        $btnFavourite.ToolTip = if ([bool]$srv.favorite) { 'Remove from favourites' } else { 'Add to favourites' }
        $btnFavourite.Style = $Window.Resources['Ghost']
        $btnFavourite.Tag = [string]$srv.name
        $btnFavourite.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        $btnFavourite.VerticalAlignment = 'Top'
        $btnFavourite.Add_Click({
            param($s, $e)
            $sv = Get-ServerByName ([string]$s.Tag)
            if (-not $sv) { return }
            Set-Prop $sv 'favorite' (-not [bool]$sv.favorite)
            Save-Servers
            Rebuild-ServerRows
        })
        [void]$topActions.Children.Add($btnFavourite)

        $btnEdit = New-Object System.Windows.Controls.Button
        $btnEdit.Content = 'Edit'
        $btnEdit.Style = $Window.Resources['Ghost']
        $btnEdit.Tag = [string]$srv.name
        $btnEdit.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        $btnEdit.VerticalAlignment = 'Top'
        $btnEdit.Add_Click({
            param($s, $e)
            $sv = Get-ServerByName ([string]$s.Tag)
            if (-not $sv) { return }
            $oldName = [string]$sv.name
            $updated = Show-ProfileEditor $sv
            if (-not $updated) { return }
            foreach ($prop in 'name','connect','soundpack','reshade','commands') { Set-Prop $sv $prop $updated.$prop }
            $shortcutUpdated = $false
            try { $shortcutUpdated = Update-ServerShortcut $oldName $sv } catch {}
            Save-Servers
            Rebuild-ServerRows
            $shortcutNote = if ($shortcutUpdated) { ' Its desktop shortcut was updated too.' } else { '' }
            $script:PlayStatus.Text = "Saved changes to $($sv.name).$shortcutNote"
        })
        [void]$topActions.Children.Add($btnEdit)

        $btnDuplicate = New-Object System.Windows.Controls.Button
        $btnDuplicate.Content = 'Duplicate'
        $btnDuplicate.Style = $Window.Resources['Ghost']
        $btnDuplicate.Tag = [string]$srv.name
        $btnDuplicate.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        $btnDuplicate.VerticalAlignment = 'Top'
        $btnDuplicate.Add_Click({
            param($s, $e)
            $sv = Get-ServerByName ([string]$s.Tag)
            if (-not $sv) { return }
            $stem = [string]$sv.name
            if ($stem.Length -gt 25) { $stem = $stem.Substring(0, 25).Trim() }
            $copyName = Get-UniqueServerName "$stem Copy"
            $copy = [pscustomobject]@{
                name = $copyName
                connect = [string]$sv.connect
                soundpack = [string]$sv.soundpack
                reshade = [string]$sv.reshade
                commands = @(Get-ProfileCommands $sv)
                lastPlayed = $null
                favorite = $false
            }
            $script:Servers = @($script:Servers) + $copy
            Save-Servers
            Rebuild-ServerRows
            $script:PlayStatus.Text = "Duplicated $($sv.name) as $copyName."
        })
        [void]$topActions.Children.Add($btnDuplicate)

        $btnRemove = New-Object System.Windows.Controls.Button
        $btnRemove.Content = 'Remove'
        $btnRemove.Style = $Window.Resources['Ghost']
        $btnRemove.Tag = [string]$srv.name
        $btnRemove.VerticalAlignment = 'Top'
        $btnRemove.Add_Click({
            param($s, $e)
            $n = [string]$s.Tag
            $r = [Windows.MessageBox]::Show("Remove '$n' from your servers? (A desktop shortcut, if you made one, stays until you delete it.)", 'Xn Fresh Deploy', 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            $script:Servers = @($script:Servers | Where-Object { [string]$_.name -ne $n })
            $shortcutRemoved = $false
            try { $shortcutRemoved = Remove-ServerShortcut $n } catch {}
            Save-Servers
            Rebuild-ServerRows
            $shortcutNote = if ($shortcutRemoved) { ' Its desktop shortcut was removed too.' } else { '' }
            $script:PlayStatus.Text = "Removed $n.$shortcutNote"
        })
        [void]$topActions.Children.Add($btnRemove)
        [void]$top.Children.Add($topActions)

        $info = New-Object System.Windows.Controls.StackPanel
        $nm = New-Object System.Windows.Controls.TextBlock
        $nm.Text = [string]$srv.name
        $nm.FontSize = 15
        $nm.FontWeight = 'SemiBold'
        $nm.Foreground = $Window.Resources['InkBrush']
        [void]$info.Children.Add($nm)
        $cn = New-Object System.Windows.Controls.TextBlock
        $cn.Text = [string]$srv.connect
        $cn.FontSize = 11.5
        $cn.Foreground = $Window.Resources['MutedBrush']
        $cn.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
        [void]$info.Children.Add($cn)
        $last = New-Object System.Windows.Controls.TextBlock
        $last.Text = Format-LastPlayed $srv.lastPlayed
        $last.FontSize = 10.5
        $last.Foreground = New-Brush '#66758C'
        $last.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
        [void]$info.Children.Add($last)
        $commandCount = @(Get-ProfileCommands $srv).Count
        if ($commandCount -gt 0) {
            $settings = New-Object System.Windows.Controls.TextBlock
            $settings.Text = "$commandCount server command(s)"
            $settings.FontSize = 10.5
            $settings.Foreground = New-Brush '#8FA4FF'
            $settings.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
            [void]$info.Children.Add($settings)
        }
        $badge = New-Object System.Windows.Controls.TextBlock
        $badge.Text = 'Checking server...'
        $badge.FontSize = 10.5
        $badge.FontWeight = 'SemiBold'
        $badge.Foreground = New-Brush '#8FA4FF'
        $badge.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        [void]$info.Children.Add($badge)
        $script:ProfileBadges[[string]$srv.name] = $badge
        Update-ProfileReadiness ([string]$srv.name)
        [void]$top.Children.Add($info)
        [void]$stack.Children.Add($top)

        # Row 2: pack pickers + play + shortcut
        $ctrl = New-Object System.Windows.Controls.DockPanel
        $ctrl.LastChildFill = $true
        $ctrl.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)

        $right = New-Object System.Windows.Controls.StackPanel
        $right.Orientation = 'Horizontal'
        [System.Windows.Controls.DockPanel]::SetDock($right, 'Right')

        $btnShortcut = New-Object System.Windows.Controls.Button
        $btnShortcut.Content = 'Make shortcut'
        $btnShortcut.Style = $Window.Resources['Ghost']
        $btnShortcut.Tag = [string]$srv.name
        $btnShortcut.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        $btnShortcut.VerticalAlignment = 'Center'
        $btnShortcut.Add_Click({
            param($s, $e)
            $sv = Get-ServerByName ([string]$s.Tag)
            if (-not $sv) { return }
            try {
                [void](New-ServerShortcut $sv)
                $script:PlayStatus.Text = "Shortcut for $($sv.name) is on your Desktop - double-click it any time to jump straight in."
            }
            catch { $script:PlayStatus.Text = "Couldn't make the shortcut: $($_.Exception.Message)" }
        })
        [void]$right.Children.Add($btnShortcut)

        $btnPlay = New-Object System.Windows.Controls.Button
        $btnPlay.Content = 'Apply and play'
        $btnPlay.Style = $Window.Resources['PrimarySm']
        $btnPlay.Tag = [string]$srv.name
        $btnPlay.VerticalAlignment = 'Center'
        $btnPlay.Add_Click({
            param($s, $e)
            $sv = Get-ServerByName ([string]$s.Tag)
            if (-not $sv) { return }
            $played = Invoke-PlayServer $sv { param($m) $script:PlayStatus.Text = "$m"; Pump-MainUi }
            if ($played) { Rebuild-ServerRows }
        })
        [void]$right.Children.Add($btnPlay)
        [void]$ctrl.Children.Add($right)

        $pickers = New-Object System.Windows.Controls.StackPanel
        $pickers.Orientation = 'Horizontal'

        $lbS = New-Object System.Windows.Controls.TextBlock
        $lbS.Text = 'SOUNDPACK'
        $lbS.FontSize = 10.5
        $lbS.FontWeight = 'SemiBold'
        $lbS.Foreground = New-Brush '#8FA4FF'
        $lbS.VerticalAlignment = 'Center'
        $lbS.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        [void]$pickers.Children.Add($lbS)

        $cbS = New-Object System.Windows.Controls.ComboBox
        $cbS.Style = $Window.Resources['DarkCombo']
        foreach ($o in $script:SoundOptions) { [void]$cbS.Items.Add($o) }
        $selS = [string]$srv.soundpack
        $cbS.SelectedItem = if ($script:SoundOptions -contains $selS) { $selS } else { 'None' }
        $cbS.Tag = "$($srv.name)|soundpack"
        $cbS.Margin = New-Object System.Windows.Thickness(0, 0, 14, 0)
        $cbS.Add_SelectionChanged({
            param($s, $e)
            if ($script:UiLoading) { return }
            $parts = ([string]$s.Tag) -split '\|', 2
            $sv = Get-ServerByName $parts[0]
            if ($sv -and $s.SelectedItem) {
                Set-Prop $sv $parts[1] ([string]$s.SelectedItem)
                Save-Servers
                $script:PlayStatus.Text = "$($parts[0]) updated - the soundpack choice was saved automatically."
            }
        })
        [void]$pickers.Children.Add($cbS)

        $lbR = New-Object System.Windows.Controls.TextBlock
        $lbR.Text = 'RESHADE LOOK'
        $lbR.FontSize = 10.5
        $lbR.FontWeight = 'SemiBold'
        $lbR.Foreground = New-Brush '#8FA4FF'
        $lbR.VerticalAlignment = 'Center'
        $lbR.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        [void]$pickers.Children.Add($lbR)

        $cbR = New-Object System.Windows.Controls.ComboBox
        $cbR.Style = $Window.Resources['DarkCombo']
        foreach ($o in $script:ReshadeOptions) { [void]$cbR.Items.Add($o) }
        $selR = [string]$srv.reshade
        $cbR.SelectedItem = if ($script:ReshadeOptions -contains $selR) { $selR } else { 'Keep current' }
        $cbR.Tag = "$($srv.name)|reshade"
        $cbR.Add_SelectionChanged({
            param($s, $e)
            if ($script:UiLoading) { return }
            $parts = ([string]$s.Tag) -split '\|', 2
            $sv = Get-ServerByName $parts[0]
            if ($sv -and $s.SelectedItem) {
                Set-Prop $sv $parts[1] ([string]$s.SelectedItem)
                Save-Servers
                $script:PlayStatus.Text = "$($parts[0]) updated - the ReShade choice was saved automatically."
            }
        })
        [void]$pickers.Children.Add($cbR)

        [void]$ctrl.Children.Add($pickers)
        [void]$stack.Children.Add($ctrl)

        $card.Child = $stack
        [void]$script:ServersPanel.Children.Add($card)
    }
    $script:UiLoading = $false
    Start-ProfileStatusChecks $view
}

$BtnTestServer.Add_Click({
    $script:BtnTestServer.IsEnabled = $false
    $script:PlayStatus.Text = 'Testing the server connection...'
    Pump-MainUi
    try {
        $result = Test-FiveMConnectTarget $script:TxtNewConnect.Text
        if ($result.Online) {
            $script:TxtNewConnect.Text = Normalize-ConnectTarget ([string]$result.Connect)
            if (-not $script:TxtNewName.Text.Trim() -and $result.Name) {
                $cleanName = ([string]$result.Name) -replace '\^[0-9]', '' -replace '[^\w \-\.]', ''
                $cleanName = $cleanName.Trim()
                if ($cleanName.Length -gt 30) { $cleanName = $cleanName.Substring(0, 30).Trim() }
                if ($cleanName) { $script:TxtNewName.Text = $cleanName }
            }
            $players = if ($result.Players) { " $($result.Players)." } else { '' }
            $script:PlayStatus.Text = "Online.$players $($result.Detail)"
        }
        else { $script:PlayStatus.Text = $result.Detail }
    }
    catch { $script:PlayStatus.Text = "Connection test failed: $($_.Exception.Message)" }
    finally { $script:BtnTestServer.IsEnabled = $true }
})

$BtnDetectServer.Add_Click({
    $script:PlayStatus.Text = 'Checking FiveM for the last or currently connected server...'
    $script:BtnDetectServer.IsEnabled = $false
    Pump-MainUi
    try {
        $hint = Get-FiveMServerHint
        if (-not $hint) {
            $script:PlayStatus.Text = 'No server was detected. Join it once in FiveM, then try again - or paste its connect code here.'
            return
        }
        $script:TxtNewConnect.Text = Normalize-ConnectTarget ([string]$hint.Connect)
        if (-not $script:TxtNewName.Text.Trim() -and $hint.Name) {
            $cleanName = ([string]$hint.Name) -replace '\^[0-9]', '' -replace '[^\w \-\.]', ''
            $cleanName = $cleanName.Trim()
            if ($cleanName.Length -gt 30) { $cleanName = $cleanName.Substring(0, 30).Trim() }
            if ($cleanName) { $script:TxtNewName.Text = $cleanName }
        }
        $kind = if ([string]$hint.Connect -match '^[a-zA-Z0-9]{4,12}$') { 'connect code' } else { 'IP and port' }
        $script:PlayStatus.Text = "Detected a $kind from $($hint.Source). Check it, choose your packs, then create the profile."
    }
    catch {
        $script:PlayStatus.Text = "FiveM detection didn't work: $($_.Exception.Message) You can still paste a connect code manually."
    }
    finally {
        $script:BtnDetectServer.IsEnabled = $true
    }
})

$BtnAddServer.Add_Click({
    $n = $TxtNewName.Text.Trim()
    $c = Normalize-ConnectTarget $TxtNewConnect.Text
    if (-not $n -or -not $c) { $script:PlayStatus.Text = 'Give the server a name and a join code or IP first.'; return }
    if ($n -notmatch '^[\w \-\.]{1,30}$') { $script:PlayStatus.Text = 'Keep the name to letters, numbers, spaces and dashes (max 30).'; return }
    if (Get-ServerByName $n) { $script:PlayStatus.Text = "You've already got a server called '$n'."; return }
    $sound = if ($CmbNewSound.SelectedItem) { [string]$CmbNewSound.SelectedItem } else { 'None' }
    $reshade = if ($CmbNewReshade.SelectedItem) { [string]$CmbNewReshade.SelectedItem } else { 'Keep current' }
    try { $commands = @(Get-ProfileCommandsFromPicker $LstNewCommands $TxtNewMouseScale $TxtNewFov) }
    catch { $script:PlayStatus.Text = $_.Exception.Message; return }
    $new = [pscustomobject]@{ name = $n; connect = $c; soundpack = $sound; reshade = $reshade; commands = $commands; lastPlayed = $null; favorite = $false }
    $script:Servers = @($script:Servers) + $new
    Save-Servers
    $TxtNewName.Text = ''
    $TxtNewConnect.Text = ''
    Initialize-ProfileCommandPicker $LstNewCommands @() $TxtNewMouseScale $TxtNewFov
    $TxtNewMouseScale.Text = ''
    $TxtNewFov.Text = ''
    $TxtNewCustomName.Text = ''
    $TxtNewCustomValue.Text = ''
    $TxtNewCustomStatus.Text = 'Enter a command name and value, then press Add command.'
    Update-ProfileCommandPicker $LstNewCommands $PnlNewMouseScale $PnlNewFov $TxtNewCommandSummary
    Rebuild-ServerRows
    $settingsNote = if ($commands.Count -gt 0) { " and $($commands.Count) server command(s)" } else { '' }
    $script:PlayStatus.Text = "Created $n with $sound, $reshade$settingsNote. The profile is ready to play."
})

$BtnRefreshLibraries.Add_Click({
    Refresh-Libraries
    Rebuild-ServerRows
    $script:PlayStatus.Text = 'Library refreshed - every profile now has the latest soundpacks and ReShade looks.'
})

$BtnManageLibraries.Add_Click({
    Show-LibraryManager
    $script:PlayStatus.Text = 'Library changes are saved and every profile has been refreshed.'
})

$BtnReshadeManager.Add_Click({
    Show-ReShadeManager
    $script:PlayStatus.Text = 'ReShade manager closed. Its health check, shader choices, and managed install record are saved.'
})

$BtnExportProfiles.Add_Click({
    try {
        $path = Export-ServerProfiles
        if ($path) { $script:PlayStatus.Text = "Exported $($script:Servers.Count) profile(s) to $path" }
    }
    catch { $script:PlayStatus.Text = "Profile export failed: $($_.Exception.Message)" }
})

$BtnPortableProfiles.Add_Click({
    try {
        $script:PlayStatus.Text = 'Building the full portable backup and verifying every included pack...'
        Pump-MainUi
        $path = Export-PortableProfiles
        if ($path) { $script:PlayStatus.Text = "Full portable backup created: $path" }
        else { $script:PlayStatus.Text = 'Portable backup cancelled.' }
    }
    catch { $script:PlayStatus.Text = "Portable backup failed: $($_.Exception.Message)" }
})

$BtnRestorePrevious.Add_Click({
    try {
        $script:PlayStatus.Text = 'Restoring the previous soundpack and ReShade setup...'
        Pump-MainUi
        $script:PlayStatus.Text = Restore-PreviousSetup
        Rebuild-ServerRows
    }
    catch { $script:PlayStatus.Text = "Restore failed: $($_.Exception.Message)" }
})

$BtnImportProfiles.Add_Click({
    try {
        $script:PlayStatus.Text = 'Opening and verifying the selected profile backup...'
        Pump-MainUi
        $result = Import-ServerProfiles
        if ($result) {
            $missing = if ($result.MissingAssignments -gt 0) { " $($result.MissingAssignments) pack assignment(s) need matching library folders." } else { '' }
            $packs = if ($result.PSObject.Properties['Soundpacks']) { " Added $($result.Soundpacks) soundpack(s) and $($result.ReShadeLooks) ReShade look(s)." } else { '' }
            $script:PlayStatus.Text = "Imported $($result.Added) profile(s); skipped $($result.Skipped).$packs$missing"
        }
        else { $script:PlayStatus.Text = 'Import cancelled.' }
    }
    catch { $script:PlayStatus.Text = "Profile import failed: $($_.Exception.Message)" }
})

$BtnOpenSounds.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($script:SoundLibDir)`"" })
$BtnOpenReshadeLib.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($script:ReshadeLibDir)`"" })

$BtnSaveSound.Add_Click({
    $n = $TxtSoundName.Text.Trim()
    if (-not $n) { $script:PlayStatus.Text = 'Type a name for the soundpack first.'; return }
    if ($n -notmatch '^[\w \-\.]{1,30}$') { $script:PlayStatus.Text = 'Keep the name to letters, numbers, spaces and dashes (max 30).'; return }
    try {
        Save-CurrentSoundpack $n
        $TxtSoundName.Text = ''
        Refresh-Libraries
        Rebuild-ServerRows
        $script:PlayStatus.Text = "Soundpack '$n' saved to the library."
    }
    catch { $script:PlayStatus.Text = [string]$_.Exception.Message }
})

$BtnSaveReshade.Add_Click({
    $n = $TxtReshadeName.Text.Trim()
    if (-not $n) { $script:PlayStatus.Text = 'Type a name for the look first.'; return }
    if ($n -notmatch '^[\w \-\.]{1,30}$') { $script:PlayStatus.Text = 'Keep the name to letters, numbers, spaces and dashes (max 30).'; return }
    try {
        Save-CurrentReshade $n
        $TxtReshadeName.Text = ''
        Refresh-Libraries
        Rebuild-ServerRows
        $script:PlayStatus.Text = "ReShade look '$n' saved to the library."
    }
    catch { $script:PlayStatus.Text = [string]$_.Exception.Message }
})

# ==============================================================================
#  SETUP tab (apps, drivers, tweaks, FiveM, ReShade install)
# ==============================================================================
$script:AppSwitches = @()
foreach ($app in $Config.apps) {
    $row = New-Object System.Windows.Controls.Grid
    $row.Margin = New-Object System.Windows.Thickness(0, 5, 0, 5)
    $c0 = New-Object System.Windows.Controls.ColumnDefinition
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::Auto
    [void]$row.ColumnDefinitions.Add($c0)
    [void]$row.ColumnDefinitions.Add($c1)

    $texts = New-Object System.Windows.Controls.StackPanel
    $texts.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
    $t1 = New-Object System.Windows.Controls.TextBlock
    $t1.Text = [string]$app.name
    $t1.FontSize = 13
    $t1.FontWeight = 'SemiBold'
    $t1.Foreground = $Window.Resources['InkBrush']
    [void]$texts.Children.Add($t1)
    $descText = if ($app.PSObject.Properties['desc'] -and $app.desc) { [string]$app.desc } else { "winget: $($app.wingetId)" }
    $t2 = New-Object System.Windows.Controls.TextBlock
    $t2.Text = $descText
    $t2.FontSize = 11
    $t2.Foreground = $Window.Resources['MutedBrush']
    $t2.TextWrapping = 'Wrap'
    [void]$texts.Children.Add($t2)
    [void]$row.Children.Add($texts)

    $sw = New-Object System.Windows.Controls.CheckBox
    $sw.Style = $Window.Resources['Switch']
    $sw.IsChecked = if ($app.PSObject.Properties['selectedByDefault']) { [bool]$app.selectedByDefault } else { $false }
    $sw.Tag = [string]$app.name
    $sw.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($sw, 1)
    [void]$row.Children.Add($sw)

    [void]$AppsPanel.Children.Add($row)
    $script:AppSwitches += $sw
}

# ==============================================================================
#  Hardware detection (drives the driver-helper suggestions)
# ==============================================================================
$script:HwSwitches = @()

function Get-HardwareInfo {
    $hw = @{ Cpu = ''; Board = ''; Gpus = @(); CpuVendor = ''; HasNvidiaGpu = $false; HasAmdGpu = $false; HasIntelGpu = $false }
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $hw.Cpu = ([string]$cpu.Name -replace '\s+', ' ').Trim()
        if     ([string]$cpu.Manufacturer -match 'AMD')   { $hw.CpuVendor = 'AMD' }
        elseif ([string]$cpu.Manufacturer -match 'Intel') { $hw.CpuVendor = 'Intel' }
    } catch {}
    try {
        $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        $hw.Board = ("$($bb.Manufacturer) $($bb.Product)").Trim()
    } catch {}
    # PCI vendor ids work even on a fresh install with no drivers at all
    try {
        foreach ($d in @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Display'" -ErrorAction Stop)) {
            $id = [string]$d.PNPDeviceID
            if     ($id -match 'VEN_10DE') { $hw.HasNvidiaGpu = $true }
            elseif ($id -match 'VEN_1002') { $hw.HasAmdGpu = $true }
            elseif ($id -match 'VEN_8086') { $hw.HasIntelGpu = $true }
        }
    } catch {}
    try {
        $names = @(Get-CimInstance Win32_VideoController -ErrorAction Stop |
                   Where-Object { $_.Name -and $_.Name -notmatch 'Basic Display|Remote|Virtual' } |
                   ForEach-Object { [string]$_.Name })
        if ($names.Count -gt 0) { $hw.Gpus = $names }
    } catch {}
    if ($hw.Gpus.Count -eq 0) {
        if ($hw.HasNvidiaGpu) { $hw.Gpus += 'NVIDIA card (no driver on it yet)' }
        if ($hw.HasAmdGpu)    { $hw.Gpus += 'AMD card (no driver on it yet)' }
        if ($hw.HasIntelGpu)  { $hw.Gpus += 'Intel graphics (no driver yet)' }
    }
    foreach ($g in $hw.Gpus) {
        if ($g -match 'NVIDIA|GeForce|RTX|GTX') { $hw.HasNvidiaGpu = $true }
        if ($g -match 'AMD|Radeon')             { $hw.HasAmdGpu = $true }
        if ($g -match 'Intel')                  { $hw.HasIntelGpu = $true }
    }
    return $hw
}

$script:Hw = Get-HardwareInfo
$hwLines = @()
if ($Hw.Cpu)   { $hwLines += "CPU:   $($Hw.Cpu)" }
if ($Hw.Board) { $hwLines += "Board: $($Hw.Board)" }
foreach ($g in $Hw.Gpus) { $hwLines += "GPU:   $g" }
$TxtHw.Text = if ($hwLines.Count -gt 0) { $hwLines -join "`r`n" }
              else { "Couldn't read your hardware - the Drivers folder still works as normal." }

$hwTools = @()
if ($Hw.HasNvidiaGpu) {
    $hwTools += @{ Id = 'nvapp'; Name = 'NVIDIA App'
                   Desc = "Installs NVIDIA's app, which grabs the right driver for your card and keeps it updated." }
}
if ($Hw.HasAmdGpu) {
    $hwTools += @{ Id = 'amdgpu'; Name = 'AMD Radeon drivers'
                   Desc = "Opens AMD's page - its Auto-Detect tool installs the right Radeon driver." }
}
if ($Hw.CpuVendor -eq 'AMD') {
    $hwTools += @{ Id = 'amdchipset'; Name = 'AMD chipset drivers'
                   Desc = "Opens AMD's driver page so its Auto-Detect tool can sort your motherboard chipset." }
}
if ($Hw.CpuVendor -eq 'Intel' -or $Hw.HasIntelGpu) {
    $hwTools += @{ Id = 'inteldsa'; Name = 'Intel Driver & Support Assistant'
                   Desc = 'Installs the official Intel tool that finds every Intel driver this PC needs.' }
}

if ($hwTools.Count -eq 0) {
    $none = New-Object System.Windows.Controls.TextBlock
    $none.Text = 'No helper tools to suggest for this hardware.'
    $none.FontSize = 11
    $none.Foreground = $Window.Resources['MutedBrush']
    [void]$HwToolsPanel.Children.Add($none)
}
foreach ($t in $hwTools) {
    $row = New-Object System.Windows.Controls.Grid
    $row.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
    $c0 = New-Object System.Windows.Controls.ColumnDefinition
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::Auto
    [void]$row.ColumnDefinitions.Add($c0)
    [void]$row.ColumnDefinitions.Add($c1)

    $texts = New-Object System.Windows.Controls.StackPanel
    $texts.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
    $t1 = New-Object System.Windows.Controls.TextBlock
    $t1.Text = [string]$t.Name
    $t1.FontSize = 12.5
    $t1.FontWeight = 'SemiBold'
    $t1.Foreground = $Window.Resources['InkBrush']
    [void]$texts.Children.Add($t1)
    $t2 = New-Object System.Windows.Controls.TextBlock
    $t2.Text = [string]$t.Desc
    $t2.FontSize = 11
    $t2.Foreground = $Window.Resources['MutedBrush']
    $t2.TextWrapping = 'Wrap'
    [void]$texts.Children.Add($t2)
    [void]$row.Children.Add($texts)

    $sw = New-Object System.Windows.Controls.CheckBox
    $sw.Style = $Window.Resources['Switch']
    $sw.IsChecked = $false
    $sw.Tag = [string]$t.Id
    $sw.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($sw, 1)
    [void]$row.Children.Add($sw)

    [void]$HwToolsPanel.Children.Add($row)
    $script:HwSwitches += $sw
}

# ==============================================================================
#  Backup & restore (browser bookmarks + FiveM settings)
# ==============================================================================
$script:BackupDir = Join-Path $ScriptDir 'Backup'
$script:BrowserDefs = @(
    @{ Name = 'Brave'
       Bookmarks = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Default\Bookmarks'
       Exes = @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe") },
    @{ Name = 'Chrome'
       Bookmarks = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Bookmarks'
       Exes = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") },
    @{ Name = 'Edge'
       Bookmarks = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Bookmarks'
       Exes = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") }
)

function Update-BackupCard {
    $info = Join-Path $script:BackupDir 'backup-info.txt'
    if (Test-Path $info) {
        $script:TxtBackupInfo.Text = (Get-Content $info -Raw).Trim()
        $script:SwRestore.IsEnabled = $true
        $script:SwRestore.IsChecked = $true
    }
    else {
        $script:TxtBackupInfo.Text = 'No backup here yet.'
        $script:SwRestore.IsEnabled = $false
        $script:SwRestore.IsChecked = $false
    }
}

function Invoke-BackupNow {
    $got = @()
    $bDir = Join-Path $script:BackupDir 'Browser'
    New-Item -ItemType Directory -Path $bDir -Force | Out-Null
    foreach ($b in $script:BrowserDefs) {
        if (Test-Path $b.Bookmarks) {
            Copy-Item $b.Bookmarks (Join-Path $bDir "$($b.Name)-Bookmarks") -Force
            $got += "$($b.Name) bookmarks"
        }
    }
    $cfx = Join-Path $env:APPDATA 'CitizenFX'
    if (Test-Path $cfx) {
        $dst = Join-Path $script:BackupDir 'CitizenFX'
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
        Copy-Item $cfx $dst -Recurse -Force
        $got += 'FiveM settings'
    }
    if ($got.Count -eq 0) {
        $script:TxtBackupInfo.Text = 'Nothing found to back up on this PC (no browser bookmarks or FiveM settings yet).'
        return
    }
    $stamp = "Backed up $(Get-Date -Format 'ddd d MMM yyyy HH:mm'): $($got -join ', ')."
    Set-Content -Path (Join-Path $script:BackupDir 'backup-info.txt') -Value $stamp -Encoding UTF8
    Update-BackupCard
}

$BtnBackupNow.Add_Click({
    try { Invoke-BackupNow }
    catch { $script:TxtBackupInfo.Text = "Backup failed: $($_.Exception.Message)" }
})

$BtnOpenBackup.Add_Click({
    New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    Start-Process explorer.exe -ArgumentList "`"$($script:BackupDir)`""
})

$BtnExportPw.Add_Click({
    $exe = $null
    foreach ($b in $script:BrowserDefs) {
        foreach ($e in $b.Exes) { if ($e -and (Test-Path $e)) { $exe = $e; break } }
        if ($exe) { break }
    }
    if (-not $exe) { $script:TxtBackupInfo.Text = 'No browser found on this PC yet - install one first.'; return }
    New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    Start-Process $exe -ArgumentList 'chrome://settings/passwords'
    $script:TxtBackupInfo.Text = "Your browser is opening its passwords page - use its menu there to Export (before a wipe) or Import (after). Save the CSV into this app's Backup folder so it travels with everything else."
})

Update-BackupCard

$script:StageUi = @{}

function New-TaskRow([string]$Id, [string]$Label) {
    $row = New-Object System.Windows.Controls.Grid
    $row.Margin = New-Object System.Windows.Thickness(2, 8, 2, 8)
    $c0 = New-Object System.Windows.Controls.ColumnDefinition
    $c0.Width = New-Object System.Windows.GridLength(32)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    [void]$row.ColumnDefinitions.Add($c0)
    [void]$row.ColumnDefinitions.Add($c1)

    $glyph = New-Object System.Windows.Controls.TextBlock
    $glyph.Text = [char]0x25CB
    $glyph.FontSize = 15
    $glyph.Foreground = $Window.Resources['MutedBrush']
    $glyph.VerticalAlignment = 'Top'
    $glyph.Margin = New-Object System.Windows.Thickness(2, 1, 0, 0)
    [void]$row.Children.Add($glyph)

    $texts = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($texts, 1)
    $label1 = New-Object System.Windows.Controls.TextBlock
    $label1.Text = $Label
    $label1.FontSize = 13.5
    $label1.FontWeight = 'SemiBold'
    $label1.Foreground = $Window.Resources['InkBrush']
    [void]$texts.Children.Add($label1)
    $detail = New-Object System.Windows.Controls.TextBlock
    $detail.Text = 'Waiting...'
    $detail.FontSize = 11.5
    $detail.Foreground = $Window.Resources['MutedBrush']
    $detail.TextWrapping = 'Wrap'
    [void]$texts.Children.Add($detail)
    [void]$row.Children.Add($texts)

    [void]$TasksPanel.Children.Add($row)
    $script:StageUi[$Id] = @{ Glyph = $glyph; Detail = $detail }
}

function Update-StageUi([string]$Id, [string]$State, [string]$Detail) {
    if (-not $script:StageUi.ContainsKey($Id)) { return }
    $ui = $script:StageUi[$Id]
    switch ($State) {
        'run'  { $ui.Glyph.Text = [char]0x25B8; $ui.Glyph.Foreground = New-Brush '#9D8FFF' }
        'ok'   { $ui.Glyph.Text = [char]0x2713; $ui.Glyph.Foreground = New-Brush '#3EE6A8' }
        'warn' { $ui.Glyph.Text = '!';          $ui.Glyph.Foreground = New-Brush '#FFC14D' }
        'fail' { $ui.Glyph.Text = [char]0x2715; $ui.Glyph.Foreground = New-Brush '#FF5C6C' }
    }
    if ($Detail) { $ui.Detail.Text = $Detail }
}

$script:Sync = [hashtable]::Synchronized(@{
    Queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    Done  = $false
})
$script:Worker = $null

$WorkerScript = {
    param($Sync, $ConfigJson, $Sel, $ScriptDir, $DriversDir)

    function Log([string]$Level, [string]$Msg)                        { $Sync.Queue.Enqueue("LOG|$Level|$Msg") }
    function Stage([string]$Id, [string]$State, [string]$Detail = '') { $Sync.Queue.Enqueue("STAGE|$Id|$State|$Detail") }

    $ErrorActionPreference = 'Continue'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}
    $Config = $ConfigJson | ConvertFrom-Json
    $UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) XnFreshDeploy/3.10'

    function Assert-TrustedDownloadUrl([string]$Url, [string[]]$AllowedHosts, [string]$Label) {
        $uri = [Uri]$Url
        if ($uri.Scheme -ne 'https' -or $AllowedHosts -notcontains $uri.DnsSafeHost.ToLowerInvariant()) {
            throw "$Label download was blocked because its URL is not on the trusted HTTPS host list: $Url"
        }
    }

    function Assert-SignedFile([string]$Path, [string[]]$AllowedPublishers, [string]$ExpectedThumbprint = '', [string]$Label = 'Downloaded file') {
        if (-not (Test-Path $Path -PathType Leaf)) { throw "$Label was not downloaded." }
        $file = Get-Item $Path
        if ($file.Length -lt 1024) { throw "$Label is unexpectedly small and may be an error page." }
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
            throw "$Label has no valid Windows digital signature (status: $($signature.Status))."
        }
        $subject = [string]$signature.SignerCertificate.Subject
        if ($ExpectedThumbprint) {
            $expected = $ExpectedThumbprint -replace '[^A-Fa-f0-9]', ''
            $actual = [string]$signature.SignerCertificate.Thumbprint -replace '[^A-Fa-f0-9]', ''
            if ($actual -ine $expected) { throw "$Label was signed with an unexpected certificate ($actual)." }
        }
        elseif ($AllowedPublishers.Count -gt 0) {
            $publisherOk = $false
            foreach ($publisher in $AllowedPublishers) { if ($subject -match $publisher) { $publisherOk = $true; break } }
            if (-not $publisherOk) { throw "$Label was signed by an unexpected publisher: $subject" }
        }
        $sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        Log 'OK' "$Label verified - $subject; SHA256 $sha256"
        return $signature
    }

    function Assert-ZipFile([string]$Path, [string]$Label) {
        if (-not (Test-Path $Path -PathType Leaf)) { throw "$Label was not downloaded." }
        $stream = [IO.File]::OpenRead($Path)
        try {
            $first = $stream.ReadByte(); $second = $stream.ReadByte()
            if ($first -ne 0x50 -or $second -ne 0x4B) { throw "$Label is not a valid ZIP archive." }
        }
        finally { $stream.Dispose() }
        $sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        Log 'OK' "$Label archive header verified; SHA256 $sha256"
    }

    function Get-WingetPath {
        $cmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        $p = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path $p) { return $p }
        return $null
    }

    function Ensure-Winget {
        $w = Get-WingetPath
        if ($w) { return $w }
        Log 'WARN' 'winget not found - bootstrapping App Installer from Microsoft...'
        try {
            $tmp = Join-Path $env:TEMP 'AppInstaller.msixbundle'
            $wingetUrl = 'https://aka.ms/getwinget'
            Assert-TrustedDownloadUrl $wingetUrl @('aka.ms') 'Microsoft App Installer'
            Invoke-WebRequest $wingetUrl -OutFile $tmp -UseBasicParsing
            if ((Get-Item $tmp).Length -lt 1MB) { throw 'Microsoft App Installer download is unexpectedly small.' }
            Log 'OK' "Microsoft App Installer package downloaded over trusted HTTPS; Windows will verify its package signature during installation. SHA256 $((Get-FileHash $tmp -Algorithm SHA256).Hash)"
            Add-AppxPackage -Path $tmp -ErrorAction Stop
            Start-Sleep -Seconds 3
            return (Get-WingetPath)
        }
        catch {
            Log 'FAIL' "winget bootstrap failed: $($_.Exception.Message)"
            Log 'INFO' 'Fix: open Microsoft Store, install/update "App Installer", then run this again.'
            return $null
        }
    }

    function Test-AppInstalled([string]$Winget, [string]$Id) {
        try {
            $p = Start-Process $Winget -ArgumentList @('list','--id',$Id,'-e','--accept-source-agreements') -Wait -PassThru -WindowStyle Hidden
            return ($p.ExitCode -eq 0)
        } catch { return $false }
    }

    function Install-App([string]$Winget, $App) {
        if (Test-AppInstalled $Winget $App.wingetId) {
            Log 'OK' "$($App.name) - already installed, skipping"
            return 'skip'
        }
        Log 'INFO' "Installing $($App.name)  ($($App.wingetId))..."
        $wgArgs = @('install','--id',$App.wingetId,'-e','--silent',
                    '--accept-package-agreements','--accept-source-agreements')
        try {
            $p = Start-Process $Winget -ArgumentList $wgArgs -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -eq 0) { Log 'OK' "$($App.name) installed"; return 'ok' }
            Log 'FAIL' "$($App.name) failed (winget exit $($p.ExitCode)) - try manually: winget install --id $($App.wingetId)"
            return 'fail'
        }
        catch { Log 'FAIL' "$($App.name): $($_.Exception.Message)"; return 'fail' }
    }

    function Install-Drivers {
        Stage 'drivers' 'run' 'Checking your Drivers folder...'
        Log 'STEP' 'DRIVERS'
        if (-not (Test-Path $DriversDir)) {
            Stage 'drivers' 'warn' "Couldn't find the Drivers folder."
            Log 'WARN' "Drivers folder not found: $DriversDir"
            return
        }
        $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
        $work = Join-Path $env:TEMP 'XnDrivers'
        if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $work -Force | Out-Null

        $files    = Get-ChildItem $DriversDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ne '.txt' }
        $archives = @($files | Where-Object { $_.Extension -in '.zip','.7z','.rar' })
        $loose    = @($files | Where-Object { $_.Extension -in '.exe','.msi' })

        if ($archives.Count -eq 0 -and $loose.Count -eq 0) {
            Stage 'drivers' 'warn' 'The folder is empty - drop your driver files in and run this again.'
            Log 'WARN' "Nothing in $DriversDir"
            return
        }

        $done = 0; $failed = 0

        foreach ($a in $archives) {
            $dest = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($a.Name))
            Stage 'drivers' 'detail' "Unpacking $($a.Name)..."
            Log 'INFO' "Extracting $($a.Name)..."
            try {
                if ($a.Extension -eq '.zip') {
                    Expand-Archive -Path $a.FullName -DestinationPath $dest -Force
                }
                elseif (Test-Path $sevenZip) {
                    & $sevenZip x $a.FullName "-o$dest" -y | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "7z exit code $LASTEXITCODE" }
                }
                else {
                    Log 'FAIL' "$($a.Name): $($a.Extension) files need 7-Zip - turn 7-Zip on in Your apps and run that first."
                    $failed++
                    continue
                }
            }
            catch { Log 'FAIL' "$($a.Name): couldn't unpack - $($_.Exception.Message)"; $failed++; continue }

            $installer = Get-ChildItem $dest -Recurse -File -Filter 'setup.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $installer) {
                $installer = Get-ChildItem $dest -Recurse -File -Filter '*.exe' -ErrorAction SilentlyContinue |
                             Sort-Object Length -Descending | Select-Object -First 1
            }
            if (-not $installer) {
                $installer = Get-ChildItem $dest -Recurse -File -Filter '*.msi' -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if (-not $installer) { Log 'WARN' "$($a.Name): no installer found inside"; $failed++; continue }

            Stage 'drivers' 'detail' "$($installer.Name) is open - click Next through it, the next one starts when it closes."
            Log 'INFO' "Running $($installer.Name)..."
            try {
                if ($installer.Extension -eq '.msi') { Start-Process msiexec.exe -ArgumentList "/i `"$($installer.FullName)`"" -Wait }
                else { Start-Process $installer.FullName -Wait }
                Log 'OK' "$($a.Name) done"
                $done++
            }
            catch { Log 'FAIL' "$($a.Name): $($_.Exception.Message)"; $failed++ }
        }

        foreach ($x in $loose) {
            Stage 'drivers' 'detail' "$($x.Name) is open - click Next through it, the next one starts when it closes."
            Log 'INFO' "Running $($x.Name)..."
            try {
                if ($x.Extension -eq '.msi') { Start-Process msiexec.exe -ArgumentList "/i `"$($x.FullName)`"" -Wait }
                else { Start-Process $x.FullName -Wait }
                Log 'OK' "$($x.Name) done"
                $done++
            }
            catch { Log 'FAIL' "$($x.Name): $($_.Exception.Message)"; $failed++ }
        }

        if ($failed -gt 0) { Stage 'drivers' 'warn' "$done done, $failed had problems - open details below." }
        else               { Stage 'drivers' 'ok'   "$done driver package$(if($done -ne 1){'s'}) installed." }
    }

    function Disable-MouseAccel {
        Stage 'mouse' 'run' 'Turning off pointer acceleration...'
        Log 'STEP' 'MOUSE'
        try {
            $k = 'HKCU:\Control Panel\Mouse'
            Set-ItemProperty -Path $k -Name MouseSpeed      -Value '0'
            Set-ItemProperty -Path $k -Name MouseThreshold1 -Value '0'
            Set-ItemProperty -Path $k -Name MouseThreshold2 -Value '0'
        }
        catch {
            Stage 'mouse' 'fail' "Couldn't change the setting - open details below."
            Log 'FAIL' "Registry write failed: $($_.Exception.Message)"
            return
        }
        try {
            if (-not ('XnNative.Mouse' -as [type])) {
                Add-Type -Namespace XnNative -Name Mouse -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
"@
            }
            [XnNative.Mouse]::SystemParametersInfo(0x0004, 0, @(0,0,0), 0x03) | Out-Null
            Stage 'mouse' 'ok' 'Acceleration is off - your mouse feels the same from now on.'
            Log 'OK' 'Mouse acceleration OFF - applied live and saved.'
        }
        catch {
            Stage 'mouse' 'ok' 'Acceleration turned off - kicks in next time you sign in.'
            Log 'OK' 'Mouse acceleration OFF in registry (applies at next sign-in).'
        }
    }

    function Get-FiveM {
        Stage 'fivem' 'run' 'Downloading FiveM...'
        Log 'STEP' 'FIVEM'
        if (Test-Path (Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app')) {
            Stage 'fivem' 'ok' 'Already on this PC - nothing to do.'
            Log 'OK' 'FiveM already installed - skipping download.'
            return
        }
        try {
            $target = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FiveM.exe'
            $fiveMUrl = [string]$Config.fivem.downloadUrl
            Assert-TrustedDownloadUrl $fiveMUrl @('runtime.fivem.net') 'FiveM'
            Invoke-WebRequest $fiveMUrl -OutFile $target -UseBasicParsing -UserAgent $UA
            [void](Assert-SignedFile $target @('Rockstar Games','CitizenFX','Cfx\.re') '' 'FiveM installer')
            Stage 'fivem' 'ok' 'Downloaded - its installer opens at the end.'
            Log 'OK' 'FiveM installer saved to Desktop.'
        }
        catch {
            if ($target -and (Test-Path $target)) { Remove-Item $target -Force -ErrorAction SilentlyContinue }
            Stage 'fivem' 'fail' "Download didn't work - open details below."
            Log 'FAIL' "FiveM download failed: $($_.Exception.Message)"
        }
    }

    function Install-ReShadeFiveM {
        Stage 'reshade' 'run' 'Getting ReShade ready...'
        Log 'STEP' 'RESHADE'
        $appDir = Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'
        if (-not (Test-Path $appDir)) {
            Stage 'reshade' 'warn' 'FiveM has to be opened once first. Open it, close it, then run this app again with just ReShade switched on.'
            Log 'WARN' 'FiveM.app not found yet - run FiveM once, then re-run with only ReShade on.'
            return
        }
        $plugins = Join-Path $appDir 'plugins'
        New-Item -ItemType Directory -Path $plugins -Force | Out-Null

        $baseManifestPath = Join-Path $plugins '.xn-reshade-base.json'
        if (Test-Path $baseManifestPath -PathType Leaf) {
            Stage 'reshade' 'ok' 'ReShade is already managed. Use the ReShade manager on Server profiles to update, repair, or change shaders.'
            Log 'OK' 'A managed ReShade installation already exists - PC setup left it untouched.'
            return
        }

        $payloadName = if ($Config.reshade.payloadZip) { [string]$Config.reshade.payloadZip } else { 'ReShadePayload.zip' }
        $payload = Join-Path $ScriptDir $payloadName
        if (Test-Path $payload) {
            Stage 'reshade' 'detail' 'Found your saved ReShade setup - putting it back...'
            Log 'INFO' "Restoring $payloadName into FiveM plugins..."
            try {
                Assert-ZipFile $payload 'Saved ReShade payload'
                Expand-Archive -Path $payload -DestinationPath $plugins -Force
                Stage 'reshade' 'ok' 'Your saved ReShade setup is back in. Home key toggles it in game.'
                Log 'OK' 'ReShade payload restored.'
            }
            catch {
                Stage 'reshade' 'fail' "Couldn't restore your saved setup - open details below."
                Log 'FAIL' "Payload extract failed: $($_.Exception.Message)"
            }
            return
        }

        Stage 'reshade' 'detail' 'Downloading the latest ReShade...'
        Log 'INFO' 'Checking latest ReShade version...'
        $ver = $null
        $reshadeThumbprint = $null
        try {
            $reshadeHome = 'https://reshade.me'
            Assert-TrustedDownloadUrl $reshadeHome @('reshade.me') 'ReShade website'
            $html = (Invoke-WebRequest $reshadeHome -UseBasicParsing -UserAgent $UA).Content
            if ($html -match '/downloads/ReShade_Setup_(\d+\.\d+\.\d+)\.exe') { $ver = $Matches[1] }
            if ($html -match '(?is)X\.509 Digital Signature Thumbprint:.{0,250}?([A-Fa-f0-9]{40})') { $reshadeThumbprint = $Matches[1] }
        }
        catch {
            Stage 'reshade' 'fail' "Couldn't reach the ReShade website - open details below."
            Log 'FAIL' "Could not reach reshade.me: $($_.Exception.Message)"
            return
        }
        if (-not $ver) {
            Stage 'reshade' 'fail' "Couldn't find the ReShade download - the site may have changed."
            Log 'FAIL' 'Could not find the ReShade download link.'
            return
        }
        if (-not $reshadeThumbprint) {
            Stage 'reshade' 'fail' "The official signing thumbprint was not found, so the download was blocked."
            Log 'FAIL' 'ReShade signing thumbprint missing from the official download page.'
            return
        }

        $setup = Join-Path $env:TEMP "ReShade_Setup_$ver.exe"
        try {
            $setupUrl = "https://reshade.me/downloads/ReShade_Setup_$ver.exe"
            Assert-TrustedDownloadUrl $setupUrl @('reshade.me') 'ReShade'
            Invoke-WebRequest $setupUrl -OutFile $setup -UseBasicParsing -UserAgent $UA
            [void](Assert-SignedFile $setup @() $reshadeThumbprint "ReShade $ver installer")
            Log 'OK' "ReShade $ver downloaded"
        }
        catch {
            if (Test-Path $setup) { Remove-Item $setup -Force -ErrorAction SilentlyContinue }
            Stage 'reshade' 'fail' "Download didn't work - open details below."
            Log 'FAIL' "ReShade download failed: $($_.Exception.Message)"
            return
        }

        $sevenZip  = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
        $dllOut    = Join-Path $env:TEMP 'XnReShade'
        $extracted = $false
        New-Item -ItemType Directory -Path $dllOut -Force | Out-Null
        if (Test-Path $sevenZip) {
            & $sevenZip e $setup "-o$dllOut" 'ReShade64.dll' -y | Out-Null
            if (Test-Path (Join-Path $dllOut 'ReShade64.dll')) { $extracted = $true }
        }

        if (-not $extracted) {
            Stage 'reshade' 'warn' "ReShade's own installer opened instead - pick GTA V and DirectX 10/11/12, then copy dxgi.dll from your GTA V folder into FiveM.app\plugins."
            Log 'WARN' 'Could not auto-extract ReShade64.dll (7-Zip missing, or the setup layout changed).'
            Start-Process $setup
            return
        }

        $managedEntries = New-Object System.Collections.ArrayList
        $managedBackup = Join-Path $appDir '.xn-reshade-base-backup'
        $managedId = [Guid]::NewGuid().ToString('N')
        New-Item -ItemType Directory -Path $managedBackup -Force | Out-Null
        function Put-ManagedReShadeFile([string]$Source, [string]$Relative, [string]$SourceLabel) {
            $pluginFull = [IO.Path]::GetFullPath($plugins).TrimEnd('\') + '\'
            $target = [IO.Path]::GetFullPath((Join-Path $plugins $Relative))
            if (-not $target.StartsWith($pluginFull, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe ReShade path: $Relative" }
            $backupRelative = ''
            if (Test-Path $target -PathType Leaf) {
                $backupRelative = "$managedId\$Relative"
                $backup = Join-Path $managedBackup $backupRelative
                $backupParent = Split-Path -Parent $backup
                if (-not (Test-Path $backupParent)) { New-Item -ItemType Directory -Path $backupParent -Force | Out-Null }
                Copy-Item -LiteralPath $target -Destination $backup -Force
            }
            $parent = Split-Path -Parent $target
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $Source -Destination $target -Force
            $targetItem = Get-Item -LiteralPath $target
            [void]$managedEntries.Add([ordered]@{
                path = $Relative; length = [int64]$targetItem.Length
                lastWriteUtcTicks = [int64]$targetItem.LastWriteTimeUtc.Ticks
                sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                source = $SourceLabel; backup = $backupRelative
            })
        }

        Put-ManagedReShadeFile (Join-Path $dllOut 'ReShade64.dll') 'dxgi.dll' 'ReShade'
        Log 'OK' 'dxgi.dll placed in FiveM.app\plugins'

        if ($Config.reshade.installShaders) {
            Stage 'reshade' 'detail' 'Adding the standard shader pack...'
            Log 'INFO' 'Downloading the standard shader pack...'
            try {
                $shZip = Join-Path $env:TEMP 'reshade-shaders.zip'
                $shaderUrl = 'https://github.com/crosire/reshade-shaders/archive/refs/heads/slim.zip'
                Assert-TrustedDownloadUrl $shaderUrl @('github.com') 'ReShade shader pack'
                Invoke-WebRequest $shaderUrl -OutFile $shZip -UseBasicParsing -UserAgent $UA
                Assert-ZipFile $shZip 'ReShade shader pack'
                $shTmp = Join-Path $env:TEMP 'XnShaders'
                if (Test-Path $shTmp) { Remove-Item $shTmp -Recurse -Force }
                Expand-Archive -Path $shZip -DestinationPath $shTmp -Force
                $src = Get-ChildItem $shTmp -Directory | Select-Object -First 1
                $dst = Join-Path $plugins 'reshade-shaders'
                New-Item -ItemType Directory -Path $dst -Force | Out-Null
                foreach ($d in 'Shaders','Textures') {
                    $s = Join-Path $src.FullName $d
                    if (Test-Path $s) {
                        foreach ($file in Get-ChildItem -LiteralPath $s -File -Recurse -Force) {
                            $relativeInKind = $file.FullName.Substring($s.TrimEnd('\').Length + 1)
                            Put-ManagedReShadeFile $file.FullName ("reshade-shaders\$d\$relativeInKind") 'Standard'
                        }
                    }
                }
                Log 'OK' 'Shader pack installed'
            }
            catch { Log 'WARN' "Shader pack failed: $($_.Exception.Message) - ReShade still works; shaders can be added later." }
        }

        $iniPath = Join-Path $plugins 'ReShade.ini'
        if (-not (Test-Path $iniPath)) {
            $ini = @(
                '[GENERAL]'
                "EffectSearchPaths=$plugins\reshade-shaders\Shaders"
                "TextureSearchPaths=$plugins\reshade-shaders\Textures"
            ) -join "`r`n"
            $iniTemp = Join-Path $env:TEMP ('XnReShade-' + [Guid]::NewGuid().ToString('N') + '.ini')
            Set-Content -Path $iniTemp -Value $ini -Encoding ASCII
            Put-ManagedReShadeFile $iniTemp 'ReShade.ini' 'Manager settings'
            Remove-Item -LiteralPath $iniTemp -Force -ErrorAction SilentlyContinue
            Log 'OK' 'ReShade.ini written'
        }
        [ordered]@{
            version = 1; installedVersion = [string]$ver; installedAt = [DateTime]::UtcNow.ToString('o')
            dllMode = 'dxgi.dll'; shaderPacks = if ($Config.reshade.installShaders) { @('Standard') } else { @() }
            customSources = @(); files = @($managedEntries)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $baseManifestPath -Encoding UTF8
        Stage 'reshade' 'ok' "ReShade $ver is in. Press Home in game to open it."
        Log 'INFO' 'First FiveM launch: the ReShade manager can find and apply the F8 acknowledgement automatically. It can also switch dxgi.dll to d3d11.dll safely if needed.'
    }

    function Install-HwTools {
        Stage 'hwtools' 'run' 'Setting up driver helpers...'
        Log 'STEP' 'DRIVER HELPERS'
        $ok = 0; $needsYou = 0

        if ($Sel.HwTools -contains 'inteldsa') {
            Stage 'hwtools' 'detail' 'Installing Intel Driver & Support Assistant...'
            $w = Ensure-Winget
            if ($w) {
                $tool = [pscustomobject]@{ name = 'Intel Driver & Support Assistant'; wingetId = 'Intel.IntelDriverAndSupportAssistant' }
                if ((Install-App $w $tool) -eq 'fail') { $needsYou++ } else { $ok++ }
            }
            else { Log 'FAIL' 'Intel Driver & Support Assistant needs winget - see the apps step for the fix.'; $needsYou++ }
        }

        if ($Sel.HwTools -contains 'nvapp') {
            Stage 'hwtools' 'detail' 'Downloading the NVIDIA App...'
            try {
                $nvidiaPage = 'https://www.nvidia.com/en-us/software/nvidia-app/'
                Assert-TrustedDownloadUrl $nvidiaPage @('www.nvidia.com') 'NVIDIA App page'
                $html = (Invoke-WebRequest $nvidiaPage -UseBasicParsing -UserAgent $UA).Content
                if ($html -match 'https://us\.download\.nvidia\.com/nvapp/client/[^"''\s\)]+?\.exe') {
                    $url = $Matches[0]
                    $exe = Join-Path $env:TEMP 'NVIDIA_App_Setup.exe'
                    Assert-TrustedDownloadUrl $url @('us.download.nvidia.com') 'NVIDIA App'
                    Invoke-WebRequest $url -OutFile $exe -UseBasicParsing -UserAgent $UA
                    [void](Assert-SignedFile $exe @('NVIDIA Corporation') '' 'NVIDIA App installer')
                    Stage 'hwtools' 'detail' 'Installing the NVIDIA App (it grabs your GPU driver)...'
                    Log 'INFO' "Installing NVIDIA App ($url)..."
                    $p = Start-Process $exe -ArgumentList '-s' -Wait -PassThru
                    if ($p.ExitCode -eq 0) {
                        Log 'OK' 'NVIDIA App installed - open it after this and it offers the right GPU driver.'
                        $ok++
                    }
                    else {
                        Log 'WARN' "Silent install didn't take (exit $($p.ExitCode)) - its installer is opening, just click through it."
                        Start-Process $exe
                        $needsYou++
                    }
                }
                else { throw 'download link not found on the page (layout may have changed)' }
            }
            catch {
                Log 'WARN' "NVIDIA App: $($_.Exception.Message) - opening the download page instead."
                try { Start-Process 'https://www.nvidia.com/en-us/software/nvidia-app/' } catch {}
                $needsYou++
            }
        }

        if (($Sel.HwTools -contains 'amdgpu') -or ($Sel.HwTools -contains 'amdchipset')) {
            Stage 'hwtools' 'detail' "Opening AMD's driver page..."
            Log 'INFO' "AMD doesn't allow direct downloads, so their page is opening - click 'Auto-Detect and Install' there and it sorts your Radeon/chipset drivers itself."
            try { Start-Process 'https://www.amd.com/en/support/download/drivers.html'; $needsYou++ }
            catch { Log 'FAIL' "Couldn't open the AMD page: $($_.Exception.Message)"; $needsYou++ }
        }

        if ($needsYou -gt 0) { Stage 'hwtools' 'warn' "$ok done, $needsYou need a couple of clicks from you - open details below." }
        else                 { Stage 'hwtools' 'ok'   'Driver helpers installed.' }
    }

    function Restore-Backup {
        Stage 'restore' 'run' 'Bringing your backup home...'
        Log 'STEP' 'RESTORE BACKUP'
        $bk = Join-Path $ScriptDir 'Backup'
        if (-not (Test-Path $bk)) {
            Stage 'restore' 'warn' 'No Backup folder found next to the app.'
            Log 'WARN' "Backup folder missing: $bk"
            return
        }
        $count = 0; $problems = 0
        $targets = @(
            @{ Name = 'Brave';  Dir = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Default'; Proc = 'brave' },
            @{ Name = 'Chrome'; Dir = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default';               Proc = 'chrome' },
            @{ Name = 'Edge';   Dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default';              Proc = 'msedge' }
        )
        foreach ($t in $targets) {
            $src = Join-Path $bk "Browser\$($t.Name)-Bookmarks"
            if (-not (Test-Path $src)) { continue }
            Stage 'restore' 'detail' "Putting $($t.Name) bookmarks back..."
            try {
                if (Get-Process -Name $t.Proc -ErrorAction SilentlyContinue) {
                    Log 'WARN' "$($t.Name) is open right now - it may overwrite the restored bookmarks when it closes. Close it and run restore again if they don't show up."
                }
                New-Item -ItemType Directory -Path $t.Dir -Force | Out-Null
                Copy-Item $src (Join-Path $t.Dir 'Bookmarks') -Force
                Log 'OK' "$($t.Name) bookmarks are back."
                $count++
            }
            catch { Log 'FAIL' "$($t.Name) bookmarks: $($_.Exception.Message)"; $problems++ }
        }
        $cfxSrc = Join-Path $bk 'CitizenFX'
        if (Test-Path $cfxSrc) {
            Stage 'restore' 'detail' 'Putting your FiveM settings back...'
            try {
                $cfxDst = Join-Path $env:APPDATA 'CitizenFX'
                New-Item -ItemType Directory -Path $cfxDst -Force | Out-Null
                Copy-Item (Join-Path $cfxSrc '*') $cfxDst -Recurse -Force
                Log 'OK' 'FiveM settings (CitizenFX folder) restored - including your ReShade acknowledgement line if you had one.'
                $count++
            }
            catch { Log 'FAIL' "FiveM settings: $($_.Exception.Message)"; $problems++ }
        }
        $csv = @(Get-ChildItem $bk -Filter '*.csv' -ErrorAction SilentlyContinue)
        if ($csv.Count -gt 0) {
            Log 'INFO' "Password CSV found in the backup ($($csv[0].Name)) - files can't restore passwords, so import it via your browser's passwords page (the Export passwords button opens it)."
        }
        if ($problems -gt 0)  { Stage 'restore' 'warn' "$count restored, $problems had problems - open details below." }
        elseif ($count -eq 0) { Stage 'restore' 'warn' 'The Backup folder was empty - nothing to bring back.' }
        else                  { Stage 'restore' 'ok'   "$count thing$(if($count -ne 1){'s'}) restored." }
    }

    function Launch-Apps {
        Stage 'launch' 'run' 'Opening your apps...'
        Log 'STEP' 'OPENING APPS'
        $opened = 0; $missed = 0
        foreach ($app in $Config.apps) {
            if ($Sel.Apps -notcontains [string]$app.name) { continue }
            if (-not $app.launchAfter) { continue }
            $exe = $null
            foreach ($c in @($app.launchPaths)) {
                if (-not $c) { continue }
                $p = [Environment]::ExpandEnvironmentVariables([string]$c)
                if (Test-Path $p) { $exe = $p; break }
            }
            if (-not $exe) {
                Log 'WARN' "$($app.name): couldn't find it to open - open it from the Start menu to sign in."
                $missed++
                continue
            }
            try {
                $wd = Split-Path $exe -Parent
                $hasArgs = $app.PSObject.Properties['launchArgs'] -and $app.launchArgs
                if ($hasArgs) { Start-Process $exe -ArgumentList ([string]$app.launchArgs) -WorkingDirectory $wd }
                else          { Start-Process $exe -WorkingDirectory $wd }
                Log 'OK' "$($app.name) opened"
                $opened++
            }
            catch { Log 'WARN' "$($app.name): couldn't open - $($_.Exception.Message)"; $missed++ }
        }
        if ($Sel.FiveM) {
            $fx = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FiveM.exe'
            if ((Test-Path $fx) -and -not (Test-Path (Join-Path $env:LOCALAPPDATA 'FiveM\FiveM.app'))) {
                Log 'INFO' 'Starting the FiveM installer...'
                try { Start-Process $fx; $opened++ } catch { Log 'WARN' "Could not start FiveM installer: $($_.Exception.Message)" }
            }
        }
        if ($missed -gt 0) { Stage 'launch' 'warn' "Opened $opened - $missed couldn't be found, open those from the Start menu." }
        else               { Stage 'launch' 'ok'   "Opened $opened app$(if($opened -ne 1){'s'}) - just sign in." }
    }

    try {
        Log 'STEP' 'XN FRESH DEPLOY'
        Log 'INFO' "Config: $ScriptDir\config.json"
        Log 'INFO' "Drivers folder: $DriversDir"

        if ($Sel.Apps.Count -gt 0) {
            Stage 'apps' 'run' 'Getting the installer ready...'
            Log 'STEP' 'APPS'
            $winget = Ensure-Winget
            if (-not $winget) {
                Stage 'apps' 'fail' "Windows' app installer isn't available - open details below for the fix."
            }
            else {
                $done = 0; $skipped = 0; $failed = 0
                foreach ($app in $Config.apps) {
                    if ($Sel.Apps -notcontains [string]$app.name) { continue }
                    Stage 'apps' 'detail' "Installing $($app.name)..."
                    switch (Install-App $winget $app) {
                        'ok'   { $done++ }
                        'skip' { $skipped++ }
                        default { $failed++ }
                    }
                }
                $parts = @("$done installed")
                if ($skipped -gt 0) { $parts += "$skipped already there" }
                if ($failed -gt 0)  { $parts += "$failed failed" }
                $sum = $parts -join ', '
                if ($failed -gt 0) { Stage 'apps' 'warn' "$sum - open details below." }
                else               { Stage 'apps' 'ok' $sum }
            }
        }

        if ($Sel.HwTools.Count -gt 0) { Install-HwTools }
        if ($Sel.Drivers) { Install-Drivers }
        if ($Sel.Mouse)   { Disable-MouseAccel }
        if ($Sel.FiveM)   { Get-FiveM }
        if ($Sel.ReShade) { Install-ReShadeFiveM }
        if ($Sel.Restore) { Restore-Backup }
        if ($Sel.Launch)  { Launch-Apps }

        Log 'STEP' 'ALL DONE'
        Log 'INFO' 'Running this again is always safe - anything already done gets skipped.'
    }
    catch {
        Log 'FAIL' "Unexpected error: $($_.Exception.Message)"
    }
    finally {
        $Sync.Done = $true
    }
}

# --- Setup tab wiring --------------------------------------------------------------
$BtnAll.Add_Click({  foreach ($sw in $script:AppSwitches) { $sw.IsChecked = $true  } })
$BtnNone.Add_Click({ foreach ($sw in $script:AppSwitches) { $sw.IsChecked = $false } })
$BtnOpenDrivers.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$($script:DriversDir)`"" })
$BtnConfig.Add_Click({ Start-Process notepad.exe -ArgumentList "`"$($script:ConfigPath)`"" })

$BtnDetails.Add_Click({
    if ($script:LogCard.Visibility -eq 'Visible') {
        $script:LogCard.Visibility = 'Collapsed'
        $script:BtnDetails.Content = 'Show details'
    } else {
        $script:LogCard.Visibility = 'Visible'
        $script:BtnDetails.Content = 'Hide details'
    }
})

$BtnBack.Add_Click({
    $script:ProgressScreen.Visibility = 'Collapsed'
    $script:SetupScreen.Visibility = 'Visible'
})

$script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(200)
$Timer.Add_Tick({
    while ($script:Sync.Queue.Count -gt 0) {
        $line = [string]$script:Sync.Queue.Dequeue()
        if ($line.StartsWith('LOG|')) {
            $p = $line -split '\|', 3
            if ($p.Count -ge 3) { Add-LogLine $p[1] $p[2] }
        }
        elseif ($line.StartsWith('STAGE|')) {
            $p = $line -split '\|', 4
            $detail = if ($p.Count -ge 4) { $p[3] } else { '' }
            if ($p.Count -ge 3) { Update-StageUi $p[1] $p[2] $detail }
        }
    }
    if ($script:Sync.Done) {
        $script:Timer.Stop()
        $script:Sync.Done = $false
        $script:Running = $false
        if ($script:Worker) {
            try { $script:Worker.Runspace.Close(); $script:Worker.Dispose() } catch {}
            $script:Worker = $null
        }
        $script:PBar.IsIndeterminate = $false
        $script:PBar.Value = 100
        $script:PTitle.Text = 'All done'

        $issues = 0
        foreach ($k in $script:StageUi.Keys) {
            $g = $script:StageUi[$k].Glyph.Text
            if ($g -eq '!' -or $g -eq [string][char]0x2715) { $issues++ }
        }
        if ($issues -gt 0) {
            $script:DoneText.Text = "Finished - $issues step$(if($issues -ne 1){'s'}) need$(if($issues -eq 1){'s'}) a look. The notes above say what to do."
        } else {
            $script:DoneText.Text = "You're set up. Sign in to your apps as they open."
        }
        $script:DoneBanner.Visibility = 'Visible'
        $script:BtnBack.IsEnabled = $true
    }
})

function Start-SetupRun($sel) {
    $apps = @($sel.Apps)
    $hwSel = @($sel.HwTools)
    $script:TasksPanel.Children.Clear()
    $script:StageUi = @{}
    if ($apps.Count -gt 0)  { New-TaskRow 'apps'    'Install your apps' }
    if ($hwSel.Count -gt 0) { New-TaskRow 'hwtools' 'Get driver helpers' }
    if ($sel.Drivers)       { New-TaskRow 'drivers' 'Set up drivers' }
    if ($sel.Mouse)        { New-TaskRow 'mouse'   'Fix mouse feel' }
    if ($sel.FiveM)        { New-TaskRow 'fivem'   'Get FiveM' }
    if ($sel.ReShade)       { New-TaskRow 'reshade' 'Add ReShade to FiveM' }
    if ($sel.Restore)       { New-TaskRow 'restore' 'Bring back your backup' }
    if ($sel.Launch)       { New-TaskRow 'launch'  'Open your apps' }

    Clear-Log
    $script:PTitle.Text = 'Setting up your PC...'
    $script:DoneBanner.Visibility = 'Collapsed'
    $script:PBar.Value = 0
    $script:PBar.IsIndeterminate = $true
    $script:BtnBack.IsEnabled = $false
    $script:SetupScreen.Visibility = 'Collapsed'
    $script:ProgressScreen.Visibility = 'Visible'
    $script:Running = $true

    $configJson = Get-Content $script:ConfigPath -Raw
    $script:Worker = [PowerShell]::Create()
    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $script:Worker.Runspace = $rs
    [void]$script:Worker.AddScript($WorkerScript).
        AddArgument($script:Sync).
        AddArgument($configJson).
        AddArgument($sel).
        AddArgument($script:ScriptDir).
        AddArgument($script:DriversDir)
    [void]$script:Worker.BeginInvoke()
    $script:Timer.Start()
}

$BtnRun.Add_Click({
    $apps = @()
    foreach ($sw in $script:AppSwitches) { if ($sw.IsChecked) { $apps += [string]$sw.Tag } }
    $hwSel = @()
    foreach ($sw in $script:HwSwitches) { if ($sw.IsChecked) { $hwSel += [string]$sw.Tag } }
    $sel = @{
        Apps    = $apps
        HwTools = $hwSel
        Drivers = [bool]$SwDrivers.IsChecked
        Mouse   = [bool]$SwMouse.IsChecked
        FiveM   = [bool]$SwFiveM.IsChecked
        ReShade = [bool]$SwReshade.IsChecked
        Restore = [bool]$SwRestore.IsChecked
        Launch  = [bool]$SwLaunch.IsChecked
    }
    if ($apps.Count -eq 0 -and $hwSel.Count -eq 0 -and -not ($sel.Drivers -or $sel.Mouse -or $sel.FiveM -or $sel.ReShade -or $sel.Restore -or $sel.Launch)) {
        $script:FooterHint.Text = 'Everything is switched off - turn on at least one thing first.'
        return
    }

    if (-not (Test-IsAdministrator)) {
        $handoff = Join-Path $env:TEMP ("XnFreshDeploy-setup-" + [Guid]::NewGuid().ToString('N') + '.json')
        try {
            $sel | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $handoff -Encoding UTF8
            $args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -RunSetup `"$handoff`""
            Start-Process powershell -ArgumentList $args -Verb RunAs -ErrorAction Stop | Out-Null
            $script:Window.Close()
        }
        catch {
            if (Test-Path $handoff) { Remove-Item $handoff -Force -ErrorAction SilentlyContinue }
            $script:FooterHint.Text = "PC setup needs administrator permission: $($_.Exception.Message)"
        }
        return
    }

    Start-SetupRun $sel
})

$Window.Add_Closing({
    param($s, $e)
    if ($script:Running) {
        $r = [Windows.MessageBox]::Show('Setup is still running - close anyway?', 'Xn Fresh Deploy', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { $e.Cancel = $true }
    }
    if (-not $e.Cancel) { Stop-ProfileStatusChecks }
})

# --- First paint --------------------------------------------------------------------
Refresh-Libraries
Rebuild-ServerRows
Set-Nav 'play'
if ($script:StartupRecoveryNote) { $script:PlayStatus.Text = $script:StartupRecoveryNote }

if ($RunSetup) {
    try {
        if (-not (Test-IsAdministrator)) { throw 'The elevated PC setup process did not receive administrator permission.' }
        $handoffPath = [IO.Path]::GetFullPath($RunSetup)
        $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        $leaf = Split-Path $handoffPath -Leaf
        if (-not $handoffPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $leaf -notmatch '^XnFreshDeploy-setup-[a-f0-9]{32}\.json$') {
            throw 'The setup handoff file is outside the allowed temporary folder.'
        }
        $startupSelection = Get-Content -LiteralPath $handoffPath -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $handoffPath -Force
        Set-Nav 'setup'
        Start-SetupRun $startupSelection
    }
    catch {
        [Windows.MessageBox]::Show("PC setup could not start:`n`n$($_.Exception.Message)", 'Xn Fresh Deploy') | Out-Null
    }
}

[void]$Window.ShowDialog()
