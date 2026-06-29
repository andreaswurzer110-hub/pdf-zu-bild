# PDF zu Bild

Konvertiert in beide Richtungen – für Android, Windows und Linux.
Gebaut mit Flutter, PDF-Rendering über pdfium (`pdfx`). App-ID: `at.aw.pdfzubild`.

Oben im Titel schaltet der Umschalter **PDF ⇄ Bild** zwischen den zwei Modi um.

## Modus „PDF → Bild"
- PDF auswählen (oder auf dem Desktop per **Drag & Drop** hineinziehen)
- einzelne oder alle Seiten umwandeln
- **DPI frei einstellbar, Standard 300** (Schieberegler + Eingabefeld, Schnellwahl 150/300/400/600)
- Format **PNG** (verlustfrei) oder **JPEG** (kleiner) wählbar
- Zielordner wählbar; **Teilen / WhatsApp** + „Ordner öffnen"

## Modus „Bild → PDF"
- Bilder wählen oder (auf dem Handy) **Kamera** nutzen
- Seiten **sortieren** und einzeln **zuschneiden**
- Darstellung: **Original**, **Schwarz-Weiß** oder **Scan** (sieht eingescannt aus)
- als PDF speichern / teilen

## PDF-Reader
- Per **„Öffnen mit"** eine PDF an die App geben → sie öffnet im Reader (mit Zoom).
- Oben der Umschalter führt direkt in den jeweiligen Modus.
- Technik: Desktop über Kommandozeilen-Argument, Android über VIEW-Intent.

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

## Android-Version bauen (lokal)
```powershell
flutter build apk --release      # APK zum direkten Installieren
flutter build appbundle --release  # AAB für den Play Store
```
Ergebnis: `build\app\outputs\flutter-apk\app-release.apk` bzw.
`build\app\outputs\bundle\release\app-release.aab`.

> Hinweis: `android/build.gradle.kts` erzwingt projektweit **compileSdk 36**,
> weil einige Plugins (file_picker, image_picker) das verlangen.

## Linux-Version bauen
Läuft automatisch in der Cloud über **GitHub Actions** (`.github/workflows/build.yml`):
bei jedem Push nach `main` oder per „Run workflow". Das Ergebnis hängt als Artefakt
`pdf-zu-bild-linux` (`.tar.gz`) am Workflow-Lauf. Lokal auf einem Linux-Rechner:
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
