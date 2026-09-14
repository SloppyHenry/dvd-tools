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

## Voraussetzungen

- Linux, Bash
- [HandBrakeCLI](https://handbrake.fr/) mit NVENC-Unterstützung
- `mkvpropedit`, `mkvmerge` (Paket `mkvtoolnix`)
- `ffprobe` (Paket `ffmpeg`)
- `python3` (nur Standardbibliothek)
- Für `dvd-auto` zusätzlich:
  - `makemkvcon` (siehe [MakeMKV-Installation](#makemkv-installation))
  - `eject`, `blkid`, `curl`
  - eine NVIDIA-GPU mit NVENC-Unterstützung

### Ubuntu/Debian

```bash
sudo apt install handbrake-cli mkvtoolnix ffmpeg python3
```

### MakeMKV-Installation

MakeMKV besteht aus einem quelloffenen Teil (`makemkv-oss`) und einer
proprietären Laufwerks-/Entschlüsselungsbibliothek (`makemkv-bin`), die nur
als fertiges Binary von MakeMKV selbst verteilt wird. Ein Ubuntu-Paket gibt
es nicht offiziell, daher wird aus den offiziellen Quellen gebaut:

```bash
sudo apt install build-essential pkg-config libc6-dev libssl-dev \
  libexpat1-dev libavcodec-dev libavutil-dev zlib1g-dev

curl -fSLO https://www.makemkv.com/download/makemkv-oss-1.18.4.tar.gz
curl -fSLO https://www.makemkv.com/download/makemkv-bin-1.18.4.tar.gz
tar xzf makemkv-oss-1.18.4.tar.gz && cd makemkv-oss-1.18.4
./configure --disable-gui && make -j"$(nproc)" && sudo make install
cd ..

tar xzf makemkv-bin-1.18.4.tar.gz && cd makemkv-bin-1.18.4
make   # fragt interaktiv nach Zustimmung zur MakeMKV-EULA
sudo make install
```

Version ggf. an die aktuell auf makemkv.com verfügbare anpassen.
MakeMKV ist kostenlos in der Beta-Phase nutzbar (rollierender Beta-Key)
bzw. mit einer gekauften Lizenz.

## Installation

```bash
git clone <repo-url> dvd-tools
cd dvd-tools
./install.sh
```

Installiert nach `~/.local/bin` (die beiden Skripte) und
`~/.local/lib/dvd-tools` (gemeinsame Funktionen). `~/.local/bin` muss in
deinem `PATH` sein.

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
