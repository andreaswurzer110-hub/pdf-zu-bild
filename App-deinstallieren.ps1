# Entfernt die Test-Version von "PDF zu Bild" wieder.
# Rechtsklick -> "Mit PowerShell ausfuehren".

$ErrorActionPreference = 'SilentlyContinue'
Get-AppxPackage *pdfzubild* | Remove-AppxPackage
Write-Host "Deinstalliert (falls vorhanden)." -ForegroundColor Green
Read-Host "Enter zum Schliessen"
