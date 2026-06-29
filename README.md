# PDF zu Bild

Wandelt PDF-Seiten in scharfe Bilder (PNG/JPEG) um – für Android, Windows und Linux.
Gebaut mit Flutter, Rendering über pdfium (`pdfx`).

## Funktionen
- PDF auswählen, einzelne oder alle Seiten umwandeln
- **DPI frei einstellbar, Standard 300** (Schieberegler + Eingabefeld, Schnellwahl 150/300/400/600)
- Format **PNG** (verlustfrei) oder **JPEG** (kleiner) wählbar
- Zielordner wählbar (Standard: gleicher Ordner wie das PDF)
- **Teilen / WhatsApp** über das System-Teilen-Menü, plus „Ordner öffnen"

## Qualität / DPI
PDF-Text ist vektorbasiert und hat keine feste Auflösung. Richtwerte:
- 150 dpi – Bildschirm
- **300 dpi – Druckqualität, scharfer Text (Standard)**
- 400–600 dpi – sehr scharf, große Dateien

> **WhatsApp-Tipp:** Für volle Schärfe entweder beim Senden **HD** aktivieren
> (das „HD"-Symbol oben in der Foto-Vorschau) oder die Bilder als
> **Dokument/Datei** anhängen. Ohne HD komprimiert WhatsApp Fotos stark.

## Starten (Entwicklung)
```powershell
cd C:\Users\awurz\Apps\PDF_zu_Bild
flutter run -d windows
```

## Windows-Version bauen
```powershell
flutter build windows --release
```
Ergebnis: `build\windows\x64\runner\Release\` – der **gesamte Ordner** ist die App
(die `.exe` braucht die DLLs und den `data`-Ordner daneben). Zum Weitergeben den
ganzen Ordner kopieren oder zippen.

## Android-Version bauen (später)
```powershell
flutter build apk --release
```
Ergebnis: `build\app\outputs\flutter-apk\app-release.apk`

## Linux-Version bauen (auf einem Linux-Rechner)
```bash
flutter config --enable-linux-desktop
flutter build linux --release
```

## Wichtige Hinweise zum Build (CMake 4.x / Visual Studio 2026)
Zwei kleine Anpassungen waren nötig, damit der Windows-Build mit dem sehr neuen
CMake 4.3 funktioniert:

1. **`windows/CMakeLists.txt`** – die Bedingung um `CMAKE_INSTALL_PREFIX` wurde
   angepasst, weil `CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` in CMake 4.x nicht
   mehr gesetzt wird (sonst Fehler „cannot create directory C:/Program Files/...").
   Diese Datei gehört zum Projekt und bleibt erhalten.

2. **pdfx-Plugin** – die Datei `DownloadProject.CMakeLists.cmake.in` im Plugin
   verlangte `cmake_minimum_required(VERSION 2.8.12)`, was CMake 4.x ablehnt
   (auf 3.5 angehoben). Diese Datei liegt im pub-Cache und muss nach einem
   pdfx-Update ggf. erneut angepasst werden, falls der Fehler
   „Compatibility with CMake < 3.5 has been removed" auftritt.
