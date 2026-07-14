param([string]$Version = '3.10')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSCommandPath
$package = Join-Path $root 'XnFreshDeploy'
$mainScript = Join-Path $package 'Xn-Setup.ps1'
$manifestPath = Join-Path $package 'RELEASE-MANIFEST.sha256'
$finalZip = Join-Path $root "XnFreshDeploy-v$Version.zip"
$partialZip = $finalZip + '.partial.zip'

foreach ($required in 'Xn-Setup.ps1','Xn-Setup.bat','config.json','servers.json','README.md','START HERE.txt','VERSION.txt','CHANGELOG.md','icon.ico') {
    if (-not (Test-Path (Join-Path $package $required) -PathType Leaf)) { throw "Release file is missing: $required" }
}

$errors = $null
$tokens = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($mainScript, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw "Xn-Setup.ps1 has $($errors.Count) PowerShell parse error(s)." }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$source = Get-Content -LiteralPath $mainScript -Raw
$xamlWindows = [regex]::Matches($source, "(?ms)@'\r?\n(<Window\b.*?</Window>)\r?\n'@")
if ($xamlWindows.Count -ne 5) { throw "Expected 5 XAML windows; found $($xamlWindows.Count)." }
foreach ($match in $xamlWindows) { [void][Windows.Markup.XamlReader]::Parse($match.Groups[1].Value) }

$config = Get-Content -LiteralPath (Join-Path $package 'config.json') -Raw | ConvertFrom-Json
$servers = Get-Content -LiteralPath (Join-Path $package 'servers.json') -Raw | ConvertFrom-Json
if (@($servers.servers).Count -ne 0) { throw 'servers.json contains personal server profiles.' }
if (@($config.apps | Where-Object selectedByDefault).Count -gt 1) { throw 'More than one optional app is selected by default.' }

$privateItems = @(Get-ChildItem -LiteralPath $package -Force -Recurse -ErrorAction Stop | Where-Object {
    $_.Name -match '^(Backup|ReShadePayload\.zip|desktop\.ini|Thumbs\.db)$' -or
    $_.Name -match '^\.xn-' -or $_.Name -match '\.(log|tmp|partial)$'
})
if ($privateItems.Count -gt 0) { throw "Private or temporary release content found: $($privateItems[0].FullName)" }

$drivers = @(Get-ChildItem -LiteralPath (Join-Path $package 'Drivers') -Force | Where-Object { $_.Name -ne 'DROP DRIVERS HERE.txt' })
$soundpacks = @(Get-ChildItem -LiteralPath (Join-Path $package 'Library\Soundpacks') -Force | Where-Object { $_.Name -ne 'WHAT GOES HERE.txt' })
$looks = @(Get-ChildItem -LiteralPath (Join-Path $package 'Library\ReShade') -Force | Where-Object { $_.Name -ne 'WHAT GOES HERE.txt' })
if ($drivers.Count -or $soundpacks.Count -or $looks.Count) { throw 'The release contains driver packages, soundpacks, or ReShade looks.' }

$textFiles = @(Get-ChildItem -LiteralPath $package -File -Recurse | Where-Object { $_.Extension -notin '.ico','.png' })
$privateText = @($textFiles | Select-String -Pattern 'C:\\Users\\','Desktop\\claude','D:\\soundpacks' -ErrorAction Stop)
if ($privateText.Count -gt 0) { throw "A local machine path was found in $($privateText[0].Path)." }

if (Test-Path $manifestPath) { Remove-Item -LiteralPath $manifestPath -Force }
$packageFull = [IO.Path]::GetFullPath($package).TrimEnd('\') + '\'
$manifestLines = @(Get-ChildItem -LiteralPath $package -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = [IO.Path]::GetFullPath($_.FullName).Substring($packageFull.Length)
    "$(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 | ForEach-Object Hash) *$relative"
})
$manifestLines | Set-Content -LiteralPath $manifestPath -Encoding ASCII

if (Test-Path $partialZip) { Remove-Item -LiteralPath $partialZip -Force }
Compress-Archive -LiteralPath $package -DestinationPath $partialZip -CompressionLevel Optimal -Force
$archive = [IO.Compression.ZipFile]::OpenRead($partialZip)
try {
    $names = @($archive.Entries | ForEach-Object { ([string]$_.FullName).Replace('\','/') })
    foreach ($requiredEntry in 'XnFreshDeploy/Xn-Setup.ps1','XnFreshDeploy/Xn-Setup.bat','XnFreshDeploy/RELEASE-MANIFEST.sha256') {
        if ($names -notcontains $requiredEntry) { throw "Release ZIP is missing $requiredEntry." }
    }
}
finally { $archive.Dispose() }

if (Test-Path $finalZip) { Remove-Item -LiteralPath $finalZip -Force }
Move-Item -LiteralPath $partialZip -Destination $finalZip
$zipItem = Get-Item -LiteralPath $finalZip
[pscustomobject]@{
    Release = $zipItem.FullName
    Version = $Version
    Bytes = $zipItem.Length
    SHA256 = (Get-FileHash -LiteralPath $finalZip -Algorithm SHA256).Hash
    XamlWindows = $xamlWindows.Count
    Files = @(Get-ChildItem -LiteralPath $package -File -Recurse).Count
}
