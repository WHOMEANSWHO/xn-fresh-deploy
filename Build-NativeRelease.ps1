param(
    [string]$Version = '4.1',
    [switch]$SkipIntegrationTest,
    [string]$SignCertificate = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSCommandPath
$project = Join-Path $root 'XnFreshDeploy.Native\XnFreshDeploy.Native.csproj'
$assets = Join-Path $root 'XnFreshDeploy.Native\release-assets'
$stageName = "XnFreshDeploy-v$Version"
$stage = Join-Path $root $stageName
$finalZip = Join-Path $root "$stageName.zip"
$partialZip = "$finalZip.partial.zip"

$dotnet = if (Get-Command dotnet -ErrorAction SilentlyContinue) { 'dotnet' }
          elseif (Test-Path "$env:ProgramFiles\dotnet\dotnet.exe") { "$env:ProgramFiles\dotnet\dotnet.exe" }
          else { throw 'dotnet SDK not found. Install .NET 8 SDK to build releases.' }

foreach ($required in 'README.md', 'START HERE.txt', 'VERSION.txt', 'config.json', 'servers.json') {
    if (-not (Test-Path (Join-Path $assets $required) -PathType Leaf)) { throw "Release asset missing: $required" }
}

if (-not (Test-Path (Join-Path (Split-Path $project) 'app.ico') -PathType Leaf)) {
    throw 'app.ico is missing. Build the icon before packaging.'
}

Write-Host "Publishing Xn Fresh Deploy $Version..."
& $dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:DebugType=None -p:DebugSymbols=false -o (Join-Path $root 'XnFreshDeploy.Native\publish-out')

$exe = Join-Path $root 'XnFreshDeploy.Native\publish-out\XnFreshDeploy.exe'
if (-not (Test-Path $exe -PathType Leaf)) { throw 'Publish did not produce XnFreshDeploy.exe' }

if (-not $SkipIntegrationTest) {
    Write-Host 'Running integration test...'
    & $exe --integration-test
    if ($LASTEXITCODE -ne 0) { throw "Integration test failed with exit code $LASTEXITCODE" }
}

if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

Copy-Item -LiteralPath $exe -Destination (Join-Path $stage 'XnFreshDeploy.exe')

if ($SignCertificate.Length -gt 0) {
    $signtool = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($null -eq $signtool) { throw 'signtool.exe not found. Install the Windows SDK or sign manually.' }
    & $signtool.Source sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /n $SignCertificate (Join-Path $stage 'XnFreshDeploy.exe')
}

foreach ($file in 'README.md', 'START HERE.txt', 'VERSION.txt', 'config.json', 'servers.json') {
    Copy-Item -LiteralPath (Join-Path $assets $file) -Destination (Join-Path $stage $file)
}
if (Test-Path (Join-Path $root 'CHANGELOG.md')) {
    Copy-Item -LiteralPath (Join-Path $root 'CHANGELOG.md') -Destination (Join-Path $stage 'CHANGELOG.md')
}
Copy-Item -LiteralPath (Join-Path $assets 'Library') -Destination (Join-Path $stage 'Library') -Recurse
Copy-Item -LiteralPath (Join-Path $assets 'Drivers') -Destination (Join-Path $stage 'Drivers') -Recurse

$servers = Get-Content -LiteralPath (Join-Path $stage 'servers.json') -Raw | ConvertFrom-Json
if (@($servers.servers).Count -ne 0) { throw 'servers.json must be empty for release builds.' }

$config = Get-Content -LiteralPath (Join-Path $stage 'config.json') -Raw | ConvertFrom-Json
if (@($config.apps | Where-Object selectedByDefault).Count -gt 1) { throw 'Only one app should be selected by default in config.json.' }

$privateItems = @(Get-ChildItem -LiteralPath $stage -Force -Recurse | Where-Object {
    $_.Name -match '^(Backup|ReShadePayload\.zip|desktop\.ini|Thumbs\.db)$' -or
    $_.Name -match '^\.xn-' -or $_.Name -match '\.(log|tmp|partial)$'
})
if ($privateItems.Count -gt 0) { throw "Private release content found: $($privateItems[0].FullName)" }

$drivers = @(Get-ChildItem -LiteralPath (Join-Path $stage 'Drivers') -Force | Where-Object { $_.Name -notmatch 'DROP DRIVER' })
$soundpacks = @(Get-ChildItem -LiteralPath (Join-Path $stage 'Library\Soundpacks') -Force | Where-Object { $_.Name -notmatch 'DROP SOUNDPACK' })
$looks = @(Get-ChildItem -LiteralPath (Join-Path $stage 'Library\ReShade') -Force | Where-Object { $_.Name -notmatch 'DROP RESHADE' })
if ($drivers.Count -or $soundpacks.Count -or $looks.Count) { throw 'Release must not include personal drivers or packs.' }

$exeHash = (Get-FileHash -LiteralPath (Join-Path $stage 'XnFreshDeploy.exe') -Algorithm SHA256).Hash
@("$exeHash  XnFreshDeploy.exe") | Set-Content -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Encoding ASCII

if (Test-Path $partialZip) { Remove-Item -LiteralPath $partialZip -Force }
Compress-Archive -LiteralPath $stage -DestinationPath $partialZip -CompressionLevel Optimal -Force
if (Test-Path $finalZip) { Remove-Item -LiteralPath $finalZip -Force }
Move-Item -LiteralPath $partialZip -Destination $finalZip

$zipItem = Get-Item -LiteralPath $finalZip
[pscustomobject]@{
    Release = $zipItem.FullName
    Folder = $stage
    Version = $Version
    Bytes = $zipItem.Length
    ExeSHA256 = $exeHash
    ZipSHA256 = (Get-FileHash -LiteralPath $finalZip -Algorithm SHA256).Hash
}
