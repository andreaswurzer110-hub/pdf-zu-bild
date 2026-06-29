# Installiert die Test-Version von "PDF zu Bild" (selbst signiertes MSIX).
#
# SO GEHT'S:  Rechtsklick auf diese Datei -> "Mit PowerShell ausfuehren".
# Es oeffnet sich kurz eine Admin-Abfrage (UAC) – das ist noetig, damit Windows
# dem Test-Zertifikat vertraut. Danach wird die App installiert.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cer  = Join-Path $root 'certs\test_cert.cer'
$msix = Join-Path $root 'build\windows\x64\runner\Release\pdf_zu_bild.msix'

# Admin-Rechte sicherstellen (startet sich selbst neu als Admin).
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList `
        "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    exit
}

if (-not (Test-Path $msix)) {
    Write-Host "MSIX nicht gefunden: $msix" -ForegroundColor Red
    Write-Host "Bitte zuerst bauen:  flutter build windows --release; dart run msix:create"
    Read-Host "Enter zum Schliessen"; exit 1
}

Write-Host "1/3  Test-Zertifikat wird vertraut..." -ForegroundColor Cyan
Import-Certificate -FilePath $cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null

Write-Host "2/3  Eventuelle alte Version wird entfernt..." -ForegroundColor Cyan
Get-AppxPackage *pdfzubild* | Remove-AppxPackage -ErrorAction SilentlyContinue

Write-Host "3/3  App wird installiert..." -ForegroundColor Cyan
Add-AppxPackage -Path $msix -ForceApplicationShutdown

Write-Host ""
Write-Host "Fertig! 'PDF zu Bild' ist jetzt im Startmenue." -ForegroundColor Green
Read-Host "Enter zum Schliessen"
