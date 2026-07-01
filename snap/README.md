# PDF zu Bild im Snap Store

Snap-Packaging für die Veröffentlichung im **Snap Store** (durchsuchbare
Store-Präsenz in Ubuntu/Zorin-„Software" und über `snap find`).

Bauweg: `base: core22` + `gnome`-Extension + `flutter`-Plugin (wie bei
notizblock-aw; die alte `flutter`-Extension ist veraltet/core18-only).

## Dateien

| Datei | Zweck |
|-------|-------|
| `snapcraft.yaml` | Build-Rezept |
| `gui/pdf-zu-bild-und-reader.desktop` | Desktop-Eintrag (inkl. PDF-„Öffnen mit") |
| `gui/pdf-zu-bild-und-reader.png` | Icon (256 px, aus `assets/icon/app_icon.png`) |

**Besonderheit:** `file_picker` öffnet den Datei-/Ordner-Dialog auf Linux über
`zenity`. Unter strict confinement ist das Host-`zenity` nicht sichtbar, deshalb
wird es über einen eigenen Part (`stage-packages: [zenity]`) mit ins Snap
gebündelt. Ohne das könnte man auf Linux keine PDF/Bild-Datei auswählen.

## Einmaliges Setup

1. **Ubuntu-One-Account** (snapcraft.io) – schon vorhanden (notizblock-aw).
2. **Snap-Name registrieren:** `pdf-zu-bild-und-reader` – geht auch per Browser
   von Windows aus über <https://snapcraft.io/register-snap> (oder auf Linux
   `snapcraft register pdf-zu-bild-und-reader`).
3. **Store-Token** als Repo-Secret `SNAPCRAFT_STORE_CREDENTIALS` hinterlegen –
   **muss diesen Snap einschließen.** Das notizblock-Token war mit
   `--snaps=notizblock-aw` beschränkt und funktioniert hier NICHT. Neues Token
   erzeugen (einmal Linux/Zorin nötig):
   ```bash
   sudo snap install snapcraft --classic
   snapcraft login
   snapcraft export-login --snaps=notizblock-aw,pdf-zu-bild-und-reader \
     --acls package_access,package_push,package_update,package_release exported.txt
   cat exported.txt   # gesamten Inhalt kopieren
   ```
   GitHub → Repo → **Settings → Secrets and variables → Actions** → Secret
   `SNAPCRAFT_STORE_CREDENTIALS` auf den kopierten Inhalt setzen/aktualisieren.
   (Token läuft per Default nach ~1 Jahr ab → dann neu erzeugen.)

## Bauen & veröffentlichen

Snap baut **nur auf Linux** – „von Windows aus" baut die GitHub-Actions-Pipeline
`.github/workflows/snap.yml` in GitHubs Cloud-Linux und lädt hoch. (Die
GitHub-Build-Verknüpfung im Store-Dashboard erscheint erst nach der 1. Revision
→ darum der CI-Weg.)

- **Nur validieren (ohne Secret):** Actions → „Snap-Build" → **Run workflow** →
  baut die `.snap` und hängt sie als Artefakt an (kein Upload). Gut für den
  ersten Probelauf.
- **Testen (edge):** dasselbe „Run workflow", Channel `edge` → baut + lädt nach
  edge. Test auf Zorin: `sudo snap install pdf-zu-bild-und-reader --edge`.
- **Live (stable):** Tag pushen → Pipeline veröffentlicht nach **stable**:
  `git tag vX.Y.Z; git push origin vX.Y.Z`.

### Alternative: alles lokal auf Zorin
```bash
sudo snap install snapcraft --classic
snapcraft                                          # baut die .snap (nutzt LXD)
sudo snap install ./pdf-zu-bild-und-reader_*.snap --dangerous
snapcraft login
snapcraft upload --release=edge pdf-zu-bild-und-reader_*.snap
```

### Channel hochstufen
Wenn edge getestet ist:
```bash
snapcraft release pdf-zu-bild-und-reader <revision> stable
```
oder im Dashboard per Klick.

> Hinweis: Canonical prüft Uploads seit 2026 teils **manuell** → die erste
> Freigabe kann etwas dauern. **Kein** KI-Einreichungs-Bann wie bei Flathub.

## Vor dem ersten echten Test prüfen (Linux-Desktop)

Snap baut das Paket, verifiziert aber nicht das Verhalten. Auf Zorin testen:

- [ ] **Datei-Dialog geht:** „PDF-Datei wählen" bzw. „Ordner wählen" öffnet den
      zenity-Dialog und die gewählte Datei/der Ordner ist lesbar/beschreibbar
      (Dateien unter `$HOME` sollten via `home`-Plug funktionieren).
- [ ] **PDF → Bild:** Umwandeln schreibt die PNG/JPEG in den gewählten Ordner.
- [ ] **Bild → PDF:** „Als PDF erstellen" + „Speichern unter…" funktioniert.
- [ ] **Reader / „Öffnen mit":** PDF aus dem Dateimanager mit der App öffnen
      (Desktop-`MimeType=application/pdf`) landet im Reader.
- [ ] **Teilen:** falls genutzt – share_plus-Verhalten auf dem Desktop prüfen.
- [ ] **Vollversion:** auf Linux ist alles gratis (keine Paywall, `_linuxFree`).
