# dvd-tools

Kleine CLI-Toolsammlung, um DVD-Rips (MKV) verlustarm zu verkleinern und/oder
DVDs direkt von der Disc weg zu rippen, zu komprimieren und sauber benannt in
eine Mediathek (Jellyfin/Plex/Radarr-kompatibel) abzulegen.

Laeuft unter **Linux (Debian/Ubuntu)** und **macOS**.

Zwei Werkzeuge:

- **`dvd-shrink`** — nimmt einen bereits vorhandenen DVD-MKV-Rip, komprimiert
  ihn per Hardware-HEVC-Encoding und legt ihn sauber benannt/getaggt ab.
- **`dvd-auto`** — Komplettpipeline: DVD einlegen, wird automatisch erkannt,
  MakeMKV rippt den Hauptfilm, der Titel wird anhand des Disc-Labels in
  einer Filmdatenbank nachgeschlagen (ohne API-Key), danach automatischer
  Hardware-Encode + Tagging.

## Plattformunterschiede

dvd-tools erkennt bei jedem Lauf selbst, welche Plattform/Hardware
vorliegt (siehe [Automatische GPU-/Encoder-Erkennung](#automatische-gpu--encoder-erkennung)
und [Automatische Wiederherstellung](#features) unten). Zwei Punkte gibt
es unter macOS nicht, weil es dafuer kein Betriebssystem-Aequivalent gibt:

| Feature | Linux | macOS |
|---|---|---|
| Hardware-Encoder | NVENC / QSV / VCE (je nach GPU) | VideoToolbox |
| Disc auswerfen | `eject` | `drutil`/`diskutil` |
| Lesegeschwindigkeit drosseln (Recovery Stufe 2) | ja (`eject -x`) | nein, wird uebersprungen |
| MakeMKV-Installation | aus Quellcode gebaut | Homebrew Cask |

**Hinweis:** Diese macOS-Unterstuetzung wurde ohne Zugriff auf ein
tatsaechliches macOS-System entwickelt (nach bestem Wissen ueber
Homebrew-Paketnamen, BSD-Userland-Unterschiede und MakeMKVs Mac-Vertrieb).
Rueckmeldungen/Fixes von macOS-Nutzern sind willkommen.

## Features

- **Automatische GPU-/Encoder-Erkennung**: prüft bei jedem Lauf live, welche
  Hardware-HEVC-Encoder die installierte HandBrakeCLI tatsächlich mitbringt
  und welche GPU vorhanden ist (NVIDIA → NVENC, Intel → QSV, AMD → VCE,
  macOS → VideoToolbox) — fällt sauber auf Software-x265 zurück, wenn nichts
  Passendes gefunden wird. Kein hartcodierter Encoder, funktioniert also
  unabhängig vom GPU-Hersteller.
- **Automatische Qualitäts-Empfehlung**: analysiert Auflösung/Bitrate der
  Quelle (Bits-pro-Pixel-Heuristik) und schlägt einen passenden CQ-Wert vor
  — grobkörnige/komplexe Quellen bekommen einen niedrigeren (besseren) Wert,
  ruhige Quellen einen höheren (kleineren)
- **Verlustfreie Ton-/Untertitel-Übernahme**: alle Spuren werden 1:1 kopiert
  (kein Re-Encode), nichts geht verloren
- **Automatische Titelerkennung ohne Anmeldung** (`dvd-auto`): liest das
  Disc-Label, bereinigt es und sucht damit in einer Filmdatenbank.
  Standardmäßig läuft das über [Wikidata](https://www.wikidata.org) — **kein
  API-Key, keine Registrierung nötig**. Wikidata führt die TMDB-ID als
  eigenes Datenfeld, das Ergebnis passt also weiterhin ins
  Namensschema. Bei eindeutigem Treffer wird automatisch übernommen (mit
  Bestätigung), bei Unsicherheit gibt es eine Auswahlliste mit Jahr und
  Laufzeit plus die Option, den Titel manuell einzugeben. Nichtssagende
  Labels (`DVD_VIDEO`, `B1_T00` …) werden erkannt und gar nicht erst
  gesucht. Details und Alternativen: [Titelerkennung](#titelerkennung).
- **Sauberes Medienserver-Namensschema**:
  ```
  Titel (Jahr) [tmdbid-ID]/Titel (Jahr) [tmdbid-ID].mkv
  ```
  kompatibel mit Jellyfin, Plex, Radarr, Kodi etc.
- **Aufgeräumte Oberfläche**: nummerierte Phasen (`▶ 3/8 Disc rippen`), damit
  während eines langen Laufs klar ist, wo man steht; gerahmte Kopf- und
  Abschlusszeile, ausgerichtete Wertetabellen und am Ende der tatsächliche
  Platzgewinn (`4.3 GB → 1.6 GB (-63 %)`). Farben werden abgeschaltet, wenn
  die Ausgabe in eine Datei/Pipe geht oder `NO_COLOR` gesetzt ist; ohne
  UTF-8-Terminal wird automatisch auf ASCII-Zeichen umgestellt.
- Kapitelmarken bleiben erhalten
- Am Ende wird gefragt, ob die Ursprungsdatei/der temporäre Rip gelöscht
  werden soll — nichts wird automatisch gelöscht
- **Live-Detailanzeige** statt stiller Fortschrittsbalken: beim Rippen
  geschriebene Datenmenge, tatsächliche Lesegeschwindigkeit in MB/s und der
  branchenübliche x-Faktor (z.B. „8.2x“, wie bei DVD-Brennern/-Laufwerken
  angegeben), beim Encoding fps und ETA von HandBrake. Die Zahlen stehen in
  festen Spalten *vor* der MakeMKV-Statusmeldung — bei schmalen Terminals
  wird also die Meldung gekürzt, nie die Geschwindigkeit.

  Den Fortschritt in Prozent liefert MakeMKV selbst (`PRGV`), sofern die
  installierte Version das beim `mkv`-Befehl tut; andernfalls wird er aus
  dem Datenzuwachs gegen die Größe der Disc bzw. des ISO-Images geschätzt
  (bei 99 % gedeckelt, da Menüs/kurze Titel nicht mitgerippt werden). Ist
  beides nicht verfügbar (z.B. unter macOS ohne `blockdev`-Äquivalent),
  läuft statt des Balkens ein Spinner mit denselben Detailzahlen.
- **Serien-/Episoden-DVDs**: standardmäßig werden nur Titel ab 20 Minuten
  gerippt, damit Menüs, Trailer und Logos wegfallen. Sind auf einer Disc
  *alle* Titel kürzer (typisch für Episoden-DVDs), erkennt `dvd-auto` das,
  sagt es und bietet einen passenden Wert an, statt einen Lesefehler zu
  vermuten. Dauerhaft einstellbar über `DVD_TOOLS_MIN_TITLE_SECONDS`.
- **Automatische Wiederherstellung bei zerkratzten/beschädigten Discs**
  (`dvd-auto`): erkennt haengende/fehlschlagende Rips (kein Datenzuwachs
  ueber laengere Zeit) und eskaliert automatisch in drei Stufen:
  1. normale Geschwindigkeit
  2. gedrosselte Lesegeschwindigkeit (4x - liest beschaedigte Discs oft
     zuverlaessiger, da weniger Vibration)
  3. [`ddrescue`](https://www.gnu.org/software/ddrescue/)-Imaging der
     gesamten Disc (zwei Durchlaeufe: erst schnell mit Ueberspringen
     kaputter Stellen, dann gezielte Retries nur dort), danach wird aus
     dem entstandenen Image gerippt statt von der Live-Disc

  Stufe 3 kann bei starker Beschaedigung deutlich laenger dauern als ein
  normaler Rip (im Extremfall Stunden statt Minuten) - ddrescues eigene,
  dafuer gebaute Live-Anzeige wird direkt durchgereicht.

  Eskaliert wird nur bei **echten** Leseproblemen: wenn der Rip haengt oder
  nach Teildaten abbricht. Schlägt er fehl, ohne dass ein einziges Byte
  geschrieben wurde, ist die Ursache eine andere (Laufwerk belegt, Rechte,
  alle Titel unter der Mindestlänge) — dann werden MakeMKVs Meldungen
  angezeigt statt eine intakte Disc stundenlang zu imagen.

## Voraussetzungen

- Linux mit `apt` (Debian/Ubuntu) oder macOS mit [Homebrew](https://brew.sh)
  — `install.sh` löst alle Abhängigkeiten automatisch auf, siehe
  [Installation](#installation)
- Für Hardware-Encoding: eine unterstützte GPU (NVIDIA/Intel/AMD unter
  Linux, jeder Mac mit macOS 10.13+ für VideoToolbox) — ohne wird
  automatisch auf Software-x265 zurückgefallen

Ohne `apt`/`brew` (andere Systeme) manuell benötigt:

- [HandBrakeCLI](https://handbrake.fr/)
- `mkvpropedit`, `mkvmerge` (Paket `mkvtoolnix`)
- `ffprobe` (Paket `ffmpeg`)
- `python3` (nur Standardbibliothek)
- Für `dvd-auto` zusätzlich: `makemkvcon` (siehe unten), `eject`, `curl`
  (nur für TMDB; die Wikidata-Erkennung nutzt Pythons Standardbibliothek)

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

### Titelerkennung

`dvd-auto` liest das Label der eingelegten DVD (z.B. `THE_GREEN_MILE`),
räumt es auf und sucht damit in einer Filmdatenbank. **Ohne jede
Einrichtung** läuft das über [Wikidata](https://www.wikidata.org):

| | Wikidata (Vorgabe) | TMDB |
|---|---|---|
| API-Key nötig | nein | ja (kostenlos) |
| liefert TMDB-ID | ja (Eigenschaft P4947) | ja |
| liefert Laufzeit | ja | nein |
| Datenbasis | sehr gut bei Kinofilmen | umfassender, aktueller |

Warum das auch bei entstellten Labels funktioniert: DVD-Labels dürfen keine
Umlaute oder Satzzeichen enthalten. Die Suche ist deshalb fehlertolerant
ausgelegt — aus `DER_HERR_DER_RINGE_DIE_GEFAEHRTEN` wird zuverlässig
*Der Herr der Ringe: Die Gefährten*. Nichtssagende Labels (`DVD_VIDEO`,
`B1_T00`, `LOGICAL_VOLUME_ID` …) werden als solche erkannt; dann wird gar
nicht erst gesucht, sondern direkt nachgefragt.

Umstellen lässt sich der Anbieter in `~/.config/dvd-tools/config`:

```bash
mkdir -p ~/.config/dvd-tools
cp config.example ~/.config/dvd-tools/config
```

```bash
DVD_TOOLS_METADATA_PROVIDER="auto"   # auto | wikidata | tmdb | off
TMDB_API_KEY=""                      # optional, siehe unten
```

`auto` nimmt TMDB, sobald ein Key eingetragen ist, und sonst Wikidata —
liefert TMDB nichts, wird zusätzlich Wikidata versucht. `off` schaltet die
Online-Suche ganz ab und fragt immer von Hand (mit dem bereinigten
Disc-Label als Vorschlag).

Einen kostenlosen TMDB-Key gibt es unter
<https://www.themoviedb.org/settings/api> — nötig ist er nicht.

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
7. Encodiert mit HandBrake (automatisch erkannter Hardware-Encoder), taggt
   die Datei
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

Hardware-HEVC-Encoder (NVENC, QSV, VCE, VideoToolbox) brauchen bei
gleicher Qualitätsstufe ca. 30-50% mehr Bitrate als Software-x265, um
dieselbe visuelle Qualität zu erreichen — das ist der Kompromiss zwischen
Geschwindigkeit und Kompressionseffizienz. Für deutlich kleinere Dateien
bei gleicher Qualität, auf Kosten der Geschwindigkeit: `pick_hevc_encoder`
in `lib/dvd-tools/platform.sh` so anpassen, dass sie immer `x265` liefert
(Software-Encoding, keine GPU-Beschleunigung).

## Lizenz

MIT, siehe [LICENSE](LICENSE). Betrifft nur den Code in diesem Repository —
HandBrake, MakeMKV, mkvtoolnix etc. haben ihre eigenen Lizenzen.
