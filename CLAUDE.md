# dvd-tools

CLI-Tools zum Rippen (MakeMKV), Komprimieren (HandBrake, Hardware-HEVC)
und sauberen Benennen/Taggen von DVDs. Läuft unter Linux (Debian/Ubuntu)
und macOS. Governance-Einschätzung und Umfangsentscheidung: `docs/status.md`.

## Struktur

```
bin/dvd-shrink              vorhandenen Rip verkleinern (interaktiv)
bin/dvd-auto                DVD einlegen -> rippen -> verkleinern -> benennen
lib/dvd-tools/common.sh     gemeinsame Funktionen, von beiden Skripten gesourced
install.sh                  installiert Abhaengigkeiten (apt/brew) + die Tools
tests/                      Regressionstests fuer die riskantesten Funktionen
.github/workflows/          CI: shellcheck + Syntaxcheck
docs/                       status.md, tech-debt.md
```

Alle drei Skripte sind reines Bash + `python3`-Einzeiler (kein Build-System,
kein Paketmanager-Ökosystem). Gemeinsame Logik gehört nach `common.sh`,
nicht dupliziert in die einzelnen Tools.

## Befehle

```bash
bash -n bin/dvd-auto bin/dvd-shrink lib/dvd-tools/common.sh install.sh   # Syntaxcheck
shellcheck bin/* lib/dvd-tools/*.sh install.sh                          # Lint (falls installiert)
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
- Neue Live-Anzeigen (Fortschritt/Status) über `progress_bar`/`spinner_line`
  in `common.sh`, nicht eigene `printf "\r..."`-Logik — die beiden kappen
  bereits korrekt auf die Terminalbreite.
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
