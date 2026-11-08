# PowerShell script to register HyperFetch Chrome Native Messaging Host
param (
    [string]$CustomExecutablePath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "HyperFetch Chrome Native Messaging Host Registration" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $scriptDir "com.hyperfetch.native_host.json"

if (-not (Test-Path $manifestPath)) {
    Write-Error "Manifest file not found: $manifestPath"
    exit 1
}

# If custom executable path provided, update manifest path property
if ($CustomExecutablePath -ne "") {
    $manifestContent = Get-Content -Raw $manifestPath | ConvertFrom-Json
    $manifestContent.path = $CustomExecutablePath
    $manifestContent | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath
    Write-Host "Updated manifest path property to: $CustomExecutablePath" -ForegroundColor Green
}

Write-Host "Manifest file: $manifestPath" -ForegroundColor Yellow

$targets = @(
    "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.hyperfetch.native_host",
    "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.hyperfetch.native",
    "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.hyperfetch.native_host",
    "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.hyperfetch.native",
    "HKCU:\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\com.hyperfetch.native_host",
    "HKCU:\Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\com.hyperfetch.native"
)

foreach ($key in $targets) {
    try {
        if (-not (Test-Path $key)) {
            New-Item -Path $key -Force | Out-Null
        }
        Set-ItemProperty -Path $key -Name "(Default)" -Value $manifestPath
        Write-Host "  [OK] Registered $key" -ForegroundColor Green
    } catch {
        Write-Warning "  [FAILED] Could not register $key: $_"
    }
}

Write-Host "`nNative Messaging Host successfully registered!" -ForegroundColor Cyan
