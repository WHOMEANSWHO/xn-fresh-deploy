# Code signing

Unsigned Windows apps trigger SmartScreen ("Windows protected your PC"). Code signing is the main fix for distribution.

## Options

### 1. Standard code signing (OV certificate)
- Buy an Organization Validation (OV) code signing certificate from a provider such as DigiCert, Sectigo, or SSL.com.
- Typical cost: about $200–400 per year.
- After validation, sign the published EXE:

```powershell
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a "XnFreshDeploy.exe"
```

### 2. Azure Trusted Signing
- Microsoft's cloud signing service for independent developers.
- Lower cost than traditional OV for small publishers.
- See: https://learn.microsoft.com/en-us/azure/trusted-signing/

### 3. Community distribution without signing
- Publish `SHA256SUMS.txt` with every release.
- Tell users to verify the hash before running.
- SmartScreen can be bypassed with **More info → Run anyway** on first launch.

## Release build with optional signing

```powershell
.\Build-NativeRelease.ps1 -Version 4.1 -SignCertificate "CN=Your Publisher Name"
```

If `-SignCertificate` is omitted, the build remains unsigned.

## What signing does not fix
- Antivirus false positives from packed single-file executables — report false positives to the vendor if needed.
- Reputation still builds over time even with a valid signature.
