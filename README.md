# dvd-tools

Kleine CLI-Toolsammlung, um DVD-Rips (MKV) verlustarm zu verkleinern und/oder
DVDs direkt von der Disc weg zu rippen, zu komprimieren und sauber benannt in
eine Mediathek (Jellyfin/Plex/Radarr-kompatibel) abzulegen.

Zwei Werkzeuge:

- **`dvd-shrink`** — nimmt einen bereits vorhandenen DVD-MKV-Rip, komprimiert
  ihn per NVIDIA NVENC (HEVC) und legt ihn sauber benannt/getaggt ab.
- **`dvd-auto`** — Komplettpipeline: DVD einlegen, wird automatisch erkannt,
  MakeMKV rippt den Hauptfilm, der Titel wird per TMDB anhand des
  Disc-Labels erraten, danach automatischer NVENC-Encode + Tagging.

## Features

- **GPU-beschleunigtes Encoding** via NVIDIA NVENC (HEVC/H.265)
- **Automatische Qualitäts-Empfehlung**: analysiert Auflösung/Bitrate der
  Quelle (Bits-pro-Pixel-Heuristik) und schlägt einen passenden CQ-Wert vor
  — grobkörnige/komplexe Quellen bekommen einen niedrigeren (besseren) Wert,
  ruhige Quellen einen höheren (kleineren)
- **Verlustfreie Ton-/Untertitel-Übernahme**: alle Spuren werden 1:1 kopiert
  (kein Re-Encode), nichts geht verloren
- **Automatische Titelerkennung** (`dvd-auto`): liest das Disc-Label,
  bereinigt es und sucht bei [TMDB](https://www.themoviedb.org/) danach.
  Bei eindeutigem Treffer wird automatisch übernommen (mit Bestätigung),
  bei Unsicherheit bekommst du eine Auswahlliste plus die Option, den
  Titel manuell einzugeben.
- **Sauberes Medienserver-Namensschema**:
  ```
  Titel (Jahr) [tmdbid-ID]/Titel (Jahr) [tmdbid-ID].mkv
  ```
  kompatibel mit Jellyfin, Plex, Radarr, Kodi etc.
- Kapitelmarken bleiben erhalten
- Am Ende wird gefragt, ob die Ursprungsdatei/der temporäre Rip gelöscht
  werden soll — nichts wird automatisch gelöscht
- **Live-Detailanzeige** statt stiller Fortschrittsbalken: beim Rippen
  tatsächliche Lesegeschwindigkeit in MB/s und dem branchenüblichen
  x-Faktor (z.B. „8.2x“, wie bei DVD-Brennern/-Laufwerken angegeben),
  beim Encoding fps und ETA von HandBrake

## Voraussetzungen

- Linux mit `apt` (Debian/Ubuntu) — `install.sh` löst alle Abhängigkeiten
  automatisch auf, siehe [Installation](#installation)
- Für NVENC-Encoding: eine NVIDIA-GPU mit NVENC-Unterstützung

Ohne `apt` (andere Distributionen) manuell benötigt:

- [HandBrakeCLI](https://handbrake.fr/) mit NVENC-Unterstützung
- `mkvpropedit`, `mkvmerge` (Paket `mkvtoolnix`)
- `ffprobe` (Paket `ffmpeg`)
- `python3` (nur Standardbibliothek)
- Für `dvd-auto` zusätzlich: `makemkvcon` (siehe unten), `eject`, `blkid`,
  `curl`

## Installation

```bash
git clone <repo-url> dvd-tools
cd dvd-tools
./install.sh
```

`install.sh` erledigt automatisch:

1. Installiert `handbrake-cli`, `mkvtoolnix`, `ffmpeg`, `python3`,
   `eject`, `curl` sowie die Build-Abhängigkeiten für MakeMKV über `apt`
2. Baut **MakeMKV** aus dem offiziellen Quellcode, falls `makemkvcon`
   noch nicht vorhanden ist (siehe [Hintergrund](#warum-wird-makemkv-aus-dem-quellcode-gebaut))
   — inklusive interaktiver Zustimmung zur MakeMKV-EULA beim ersten Mal
3. Prüft, ob eine NVIDIA-GPU/Treiber vorhanden ist (Warnung, kein Abbruch,
   falls nicht)
4. Installiert `dvd-shrink`/`dvd-auto` nach `~/.local/bin` und die
   gemeinsame Bibliothek nach `~/.local/lib/dvd-tools`

`~/.local/bin` muss in deinem `PATH` sein — das Skript weist am Ende
darauf hin, falls nicht.

Andere MakeMKV-Version bauen: `MAKEMKV_VERSION=1.18.4 ./install.sh`

### Warum wird MakeMKV aus dem Quellcode gebaut?

MakeMKV besteht aus einem quelloffenen Teil (`makemkv-oss`) und einer
proprietären Laufwerks-/Entschlüsselungsbibliothek (`makemkv-bin`), die nur
als fertiges Binary von MakeMKV selbst verteilt wird. Ein natives
Ubuntu-Paket gibt es nicht offiziell (nur ein Flatpak, das den
Geräte-/USB-Zugriff sandboxt und für ein CLI-Tool wie `dvd-auto` unnötige
Komplexität bedeutet) — daher baut `install.sh` aus den offiziellen
Quellen: `makemkv-oss` wird kompiliert (`--disable-gui`, keine Qt-GUI
nötig), `makemkv-bin` als offizielles Binärpaket installiert. MakeMKV ist
kostenlos in der Beta-Phase nutzbar (rollierender Beta-Key) bzw. mit einer
gekauften Lizenz.

### Optional: automatische Titelerkennung einrichten

`dvd-auto` kann Filmtitel automatisch anhand des Disc-Labels erkennen. Dafür
wird ein kostenloser [TMDB-API-Key](https://www.themoviedb.org/settings/api)
benötigt:

```bash
mkdir -p ~/.config/dvd-tools
cp config.example ~/.config/dvd-tools/config
# TMDB_API_KEY="..." in der Datei eintragen
```

Ohne API-Key funktioniert `dvd-auto` weiterhin, fragt dann aber immer nach
Titel/Jahr/TMDB-ID von Hand (mit dem bereinigten Disc-Label als Vorschlag).

## Verwendung

### dvd-shrink — vorhandenen Rip verkleinern

```bash
dvd-shrink [Ausgabeordner]   # Standard: aktuelles Verzeichnis
```

Listet alle `.mkv`-Dateien im Ordner auf, du wählst eine aus, gibst Titel
(+ optional Jahr/TMDB-ID) an. Das Tool schlägt eine Qualitätsstufe vor,
encodiert, taggt und fragt am Ende, ob das Original gelöscht werden soll.

### dvd-auto — DVD einlegen, Rest läuft automatisch

```bash
dvd-auto [Ausgabeordner]     # Standard: aktuelles Verzeichnis
```

Ablauf:

1. Optisches Laufwerk wird erkannt (bei mehreren wird gefragt, welches)
2. Wartet, bis eine DVD eingelegt wird
3. Liest das Disc-Label, sucht den Titel bei TMDB, fragt bei Unsicherheit
   nach
4. Rippt den Hauptfilm (größter Titel) mit MakeMKV, Fortschrittsbalken
   inklusive
5. Wirft die Disc aus
6. Schlägt eine Encoding-Qualität vor
7. Encodiert mit NVENC/HandBrake, taggt die Datei
8. Fragt, ob der temporäre Rip gelöscht werden soll

Laufwerk manuell erzwingen:

```bash
DVD_AUTO_DRIVE=/dev/sr0 dvd-auto ~/Filme
```

## Namensschema

Ausgabedateien landen als:

```
<Ausgabeordner>/Titel (Jahr) [tmdbid-ID]/Titel (Jahr) [tmdbid-ID].mkv
```

Jahr und TMDB-ID sind optional; ohne sie wird der jeweilige Teil einfach
weggelassen.

## Warum sind die Ausgabedateien nicht winzig?

NVENC (Hardware-HEVC) braucht bei gleicher Qualitätsstufe ca. 30-50% mehr
Bitrate als Software-x265, um dieselbe visuelle Qualität zu erreichen —
das ist der Kompromiss zwischen Geschwindigkeit und Kompressionseffizienz.
Für deutlich kleinere Dateien bei gleicher Qualität: `-e x265` statt
`-e nvenc_h265` in `lib/dvd-tools/common.sh` (`encode_to_hevc`), dafür ohne
GPU-Beschleunigung und entsprechend langsamer.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Betrifft nur den Code in diesem Repository —
HandBrake, MakeMKV, mkvtoolnix etc. haben ihre eigenen Lizenzen.
