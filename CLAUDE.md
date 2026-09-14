# dvd-tools

CLI-Tools zum Rippen (MakeMKV), Komprimieren (HandBrake, Hardware-HEVC)
und sauberen Benennen/Taggen von DVDs. Läuft unter Linux (Debian/Ubuntu)
und macOS. Governance-Einschätzung und Umfangsentscheidung: `docs/status.md`.

## Struktur

```
bin/dvd-shrink                  vorhandenen Rip verkleinern (interaktiv)
bin/dvd-auto                    DVD einlegen -> rippen -> verkleinern -> benennen
lib/dvd-tools/common.sh         duenner Loader, sourced die Module unten
lib/dvd-tools/platform.sh       Linux/macOS-Abstraktion, GPU-/Encoder-Erkennung
lib/dvd-tools/ui.sh             Darstellungsschicht: Farben/Glyphen, Rahmen, Schritte,
                                Prompts, Fortschrittsbalken/Spinner, Groessenformate
lib/dvd-tools/naming.sh         Namensschema, XML-Tagging
lib/dvd-tools/quality.sh        CQ-Qualitaets-Heuristik
lib/dvd-tools/identify.sh       Disc-Label-Bereinigung, TMDB-Suche
lib/dvd-tools/rip.sh            MakeMKV-Rip + Recovery-Eskalation (ddrescue)
lib/dvd-tools/encode.sh         HandBrake-Encode
install.sh                      installiert Abhaengigkeiten (apt/brew) + die Tools
tests/                          Regressionstests fuer die riskantesten Funktionen
.github/workflows/               CI: shellcheck + Syntaxcheck
docs/                            status.md, tech-debt.md
```

Alle Skripte sind reines Bash + `python3`-Einzeiler (kein Build-System,
kein Paketmanager-Ökosystem). Gemeinsame Logik gehört in das passende
`lib/dvd-tools/*.sh`-Modul, nicht dupliziert in die einzelnen Tools. Neue
Module werden in `common.sh`s Ladeschleife eingetragen. Richtwert ~300,
harte Grenze 500 Zeilen pro Datei — bei Ueberschreitung aufteilen, nicht
weiterschreiben.

## Befehle

```bash
bash -n bin/dvd-auto bin/dvd-shrink lib/dvd-tools/*.sh install.sh   # Syntaxcheck
shellcheck bin/* lib/dvd-tools/*.sh install.sh                      # Lint (falls installiert)
tests/run.sh                                                            # Regressionstests
```

Manuelles Testen von Rip-/Encode-Logik: über simulierte Tools in `PATH`
(Fake-`makemkvcon`/`ddrescue`/`eject`-Skripte), siehe `tests/` für Beispiele.
Kein echter Disc-Zugriff nötig, um die Steuerlogik zu verifizieren.

## Konventionen

- Variablen aus Nutzereingabe (Filmtitel, Disc-Label, TMDB-Ergebnisse) nie
  direkt in `python3 -c "..."`-Strings interpolieren — immer über `argv`
  oder `stdin` durchreichen. Ebenso: Text, der in generierte XML/JSON landet,
  escapen (siehe `xml_escape` in `common.sh`).
- Plattformunterschiede (Linux/GNU vs. macOS/BSD) über die Helfer in
  `common.sh` kapseln (`is_macos`, `now_seconds`, `resolve_path`,
  `file_size_bytes`, `dir_size_bytes`, `eject_disc`, `run_unbuffered`) statt
  `date`/`readlink`/`stat`/`du`/`stdbuf` direkt mit GNU-Flags aufzurufen.
- Encoder-Wahl ist immer dynamisch (`pick_hevc_encoder`) — nie einen
  Encoder-Namen hartkodieren, auch nicht testweise.
- **Jede** Terminalausgabe läuft über `ui.sh`, nie über nacktes `echo`/`printf`
  oder `read -rp`. Vorhanden sind: `header`, `step`/`substep`, `info`, `ok`,
  `warn`, `err`, `kv`/`kv_full`, `menu_item`, `hr`, `ask`, `confirm`,
  `progress_bar`/`spinner_line`, `human_bytes`, `size_summary`. Nur so bleibt
  das Erscheinungsbild einheitlich und die Fallbacks (kein Farbterminal,
  `NO_COLOR`, kein UTF-8) greifen überall.
- Live-Anzeigen (Fortschritt/Status) ausschließlich über `progress_bar`/
  `spinner_line`, nicht eigene `printf "\r..."`-Logik — die beiden kappen
  bereits korrekt auf die Terminalbreite. In der Label-Zeile stehen feste
  Zahlenspalten **vor** variablem Text, damit beim Kappen nie die Messwerte
  wegfallen.
- `step` nummeriert automatisch anhand von `STEP_TOTAL` (im jeweiligen Tool
  gesetzt). Kommt eine Phase dazu, muss `STEP_TOTAL` mitwachsen.
- Neue Glyphen immer als `G_*`-Paar (UTF-8 + ASCII) im Kopf von `ui.sh`
  definieren, nie direkt im Code — sonst bricht der ASCII-Fallback.
- Namensschema für Ausgabedateien ist fest:
  `Titel (Jahr) [tmdbid-ID]/Titel (Jahr) [tmdbid-ID].mkv` (Jahr/ID optional),
  erzeugt über `build_basename` — nicht von Hand zusammenbauen.

## Was hier bewusst fehlt

Siehe `docs/status.md` für die vollständige Begründung. Kurzfassung: kein
Threat-Model-Dokument, keine DSGVO-Prozesse, keine Staging-Umgebung, keine
volle Testpyramide/Coverage-Gate, keine ADRs pro Entscheidung, keine
Postmortem-Struktur — unverhältnismäßig für ein lokales Ein-Personen-Tool
ohne Netzwerkdienst und ohne Nutzerdaten. Nicht aus Nachlässigkeit
weggelassen, sondern bewusst und begründet.
