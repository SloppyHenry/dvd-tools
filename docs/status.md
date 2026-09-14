# Status & Governance-Einschätzung

## Projekteinordnung (Block A, sinngemäß)

- **Projekt:** dvd-tools — CLI-Tools zum Rippen/Komprimieren/Benennen von DVDs
- **Nutzerkreis:** eine Person (Projekteigentümer), lokale Nutzung auf eigener
  Maschine. Repo ist öffentlich auf GitHub, aber ohne aktive andere Nutzer/
  Mitwirkende.
- **Personenbezogene Daten:** keine. Einzige "sensible" Konfiguration ist ein
  optionaler TMDB-API-Key in `~/.config/dvd-tools/config` (lokal, nicht im
  Repo, nicht übertragen außer an TMDB selbst für Suchanfragen).
- **Auth/Accounts/Payments:** keine.
- **Externe Systeme:** TMDB-API (Lesezugriff, öffentliche Suchanfragen),
  lokale Tools (MakeMKV, HandBrakeCLI, mkvtoolnix, ddrescue) als
  Prozessaufrufe, kein Netzwerkdienst, kein eigener Server.
- **Vertrieb:** kein App Store, kein Produkt — persönliches Werkzeug, das
  andere sich per `git clone` + `install.sh` selbst installieren können.
- **Stack:** Bash + Python3-Einzeiler, kein typisiertes Build-System, keine
  Datenbank.

## Einschätzung: was gilt, was entfällt

Das Rahmenwerk ist für produktionsreife Apps mit Nutzerkreis und
Datenverarbeitung ausgelegt. dvd-tools ist ein lokales Ein-Personen-CLI-Tool.
Entsprechend reduziert:

### Übernehmen (leichtgewichtig)

| Punkt | Umsetzung |
|---|---|
| `CLAUDE.md` | Kurz, <100 Zeilen: Zweck, Struktur, Konventionen, Testbefehle |
| Minimal-Regeln | In `CLAUDE.md` integriert statt eigener `.claude/rules/`-Dateien (Projekt hat nur 4 Quelldateien, eigene Regeldateien wären Overhead) |
| Ein bis zwei Hooks | `PostToolUse` auf Write/Edit: `bash -n` (Syntaxcheck) + `shellcheck` falls installiert. Kein Test-/Stop-Hook nötig (kein automatisierter Testlauf, s.u.) |
| Leichte CI | GitHub Actions: `shellcheck` + `bash -n` bei jedem Push. Kein Build/Typecheck/Coverage-Gate (macht in Bash ohne Testsuite keinen Sinn) |
| Minimal-Tests | Ein paar Shell-basierte Regressionstests für die riskantesten Funktionen (`build_basename`, `suggest_quality`-Heuristik, `identify_from_label`-Verzweigungen) statt volle Testpyramide — genau die Art von Tests, die in dieser Session bereits ad hoc mit simulierten Tools geschrieben wurden, jetzt dauerhaft im Repo statt Wegwerf-Skripte |
| `docs/tech-debt.md` | Ja — es gibt echte offene Punkte (macOS ungetestet, kein TMDB-Rate-Limit-Handling, ddrescue-Eskalation nur simuliert getestet) |
| Kurzer Sicherheitsabsatz statt Threat-Model-Dokument | Haupt-Angriffsfläche ist Command-Injection über Nutzereingaben (Filmtitel, Pfade) in Shell-Aufrufen — das wird konkret geprüft, siehe unten |
| `.env.example`-Äquivalent | Bereits vorhanden (`config.example`) |

### Bewusst reduziert/weglassen

| Punkt | Warum nicht |
|---|---|
| Vollständiges Threat-Model, STRIDE | Kein Netzwerkdienst, keine Trust-Boundary zu fremden Nutzern — Angriffsfläche ist lokal (Nutzer greift selbst per CLI zu) |
| DSGVO/Auskunfts-/Löschkonzept | Keine personenbezogenen Daten anderer Personen, keine Nutzer außer dem Projekteigentümer selbst |
| Staging-Umgebung | Ergibt für ein lokales CLI-Tool keinen Sinn |
| Observability (Health-Endpoint, Metriken, Crash-Reporting) | Kein laufender Dienst |
| Volle Testpyramide, Coverage-Gate ≥80% | Unverhältnismäßig für ein 4-Datei-Bash-Projekt ohne bestehende Testinfrastruktur; würde mehr Zeit kosten als das eigentliche Tool |
| Threat Model / SCA-Scan für Dependencies | Abhängigkeiten sind System-/Homebrew-Pakete (apt/brew), kein Lockfile-Ökosystem wie npm/pip — SCA-Tools greifen hier nicht |
| ADRs für jede Entscheidung | Wesentliche Entscheidungen (NVENC→dynamische Encoder-Wahl, MakeMKV aus Quellcode, Namensschema) sind bereits in Commit-Messages und README dokumentiert; ein separates ADR-Verzeichnis für 4 Dateien wäre Prozess-Overhead |
| Subagents für Dependency-Audit/Log-Analyse | Projekt zu klein, kein wiederkehrender Bedarf |
| Semantic Versioning + CHANGELOG.md | Kann später sinnvoll werden, aktuell (noch keine Releases/Tags) verfrüht — schlage vor, das ab dem ersten "stabilen" Tag einzuführen, nicht jetzt rückwirkend für die gesamte Historie |
| Phase 4 (App-Store-Compliance) | Entfällt komplett — kein App-Store-Vertrieb |
| Postmortems | Noch kein Produktivvorfall; Verzeichnis wird bei Bedarf angelegt, nicht vorab leer geschaffen |
| Pre-Commit-Hooks (lokal, zusätzlich zu Claude-Hooks) | Der Claude-Hook deckt denselben Zweck ab (Syntax-/Lint-Check bei jeder Änderung); ein zusätzliches separates Git-Hook-System wäre Redundanz für ein Ein-Personen-Projekt |

## Freigabe

Umfang am 2026-09-14 vom Projekteigentümer freigegeben ("passt so, leg los").

## Umgesetzt (Phase 0, reduzierter Umfang)

- `CLAUDE.md` (Struktur, Befehle, Konventionen, bewusste Auslassungen)
- `.claude/settings.json`: Hook, der nach Write/Edit auf Shell-Dateien
  automatisch `bash -n` + `shellcheck` laufen lässt
- `.github/workflows/ci.yml`: Syntaxcheck + ShellCheck (nur warning+,
  info-Level-Stilhinweise brechen den Build nicht) + Regressionstests
- `tests/run.sh`: Regressionstests für die reinen, riskantesten Funktionen
  (`build_basename`, `xml_escape`/`write_tags_xml`, `clean_disc_label`,
  `similarity`, `truncate_text`, Terminalbreiten-Grenzen von
  `progress_bar`/`spinner_line`)
- `docs/tech-debt.md`: bekannte offene Punkte mit Priorität/Begründung

### Konkrete Sicherheitsprüfung (statt vollem Threat-Model-Dokument)

Fokussiert auf die reale Angriffsfläche — Nutzereingaben (Filmtitel,
Disc-Label, TMDB-Suchergebnisse), die in Shell-/Python-Aufrufe und
generierte XML-Dateien einfließen:

- **Gefunden & gefixt:** `$sim` wurde direkt in einen `python3 -c`-String
  interpoliert statt als Argument übergeben (aktuell nicht ausnutzbar, da
  `similarity()` immer nur eine formatierte Fließkommazahl liefert, aber
  falsches Muster) → jetzt über `argv` durchgereicht.
- **Gefunden & gefixt:** Filmtitel/Jahr wurden unescaped in die
  MKV-Tags-XML eingebettet — ein Titel mit `&` (z. B. "Fast & Furious",
  kein Sonderfall, ein alltäglicher Titel) hätte die XML ungültig gemacht
  → `xml_escape()` ergänzt, mit Test gegen echtes XML-Parsing abgesichert.
- **Gefunden & gefixt (durch Testfall entdeckt):** `build_basename` löschte
  dateisystem-verbotene Zeichen ersatzlos statt sie zu ersetzen — ein Titel
  wie "AC/DC" wäre zu "ACDC" verschmolzen → ersetzt durch Leerzeichen +
  Zusammenziehen doppelter Leerzeichen.
- Restliche Nutzereingaben (TMDB-Suchquery, Disc-Label) laufen bereits
  sicher über `curl --data-urlencode` bzw. `stdin` in Python statt über
  String-Interpolation — keine weiteren Funde.
