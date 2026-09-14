# Bekannte offene Punkte

Bewusst aufgeschobene oder nicht abgedeckte Punkte, mit Begründung und
Priorität. Nichts hier ist "vergessen" — es ist eine bewusste Entscheidung,
den Aufwand für ein Ein-Personen-Hobbyprojekt verhältnismäßig zu halten
(siehe `docs/status.md`).

## macOS-Zweig nie auf echter Hardware getestet

**Priorität: mittel** (blockiert macOS-Nutzung im Zweifel komplett, betrifft
aber niemanden, solange kein Mac zum Testen verfügbar ist)

Die gesamte macOS-Unterstützung (Homebrew-Installation, VideoToolbox-
Encoder, `drutil`/`diskutil` statt `eject`, übersprungene
Geschwindigkeitsdrosselung) wurde ohne Zugriff auf echtes macOS entwickelt.
Logik wurde über `DVD_TOOLS_OS`-Override simuliert, aber z. B. tatsächliche
Homebrew-Paketnamen (`brew install handbrake`) und der genaue Pfad des
MakeMKV-Cask-Bundles sind nicht verifiziert.

→ Sollte vor echter Nutzung einmal auf einem Mac durchlaufen werden.

## Kein TMDB-Rate-Limit-Handling

**Priorität: niedrig**

`tmdb_search` behandelt HTTP-429-Antworten (Rate Limit) nicht gesondert —
ein fehlgeschlagener Request führt einfach zum Fallback auf manuelle
Eingabe. Für die erwartete Nutzung (ein Nutzer, gelegentliche Anfragen)
unkritisch.

## Kein Timeout auf den TMDB-Request selbst

**Priorität: niedrig**

`curl` in `tmdb_search` hat kein explizites `--max-time`. Bei einem hängenden
Netzwerk würde `dvd-auto` an dieser Stelle unbegrenzt warten. Für ein
interaktives Ein-Personen-Tool akzeptabel (Ctrl-C jederzeit möglich), wäre
aber eine einfache Verbesserung.

## ddrescue-Eskalationsstufe nur mit simulierten Tools getestet

**Priorität: mittel**

Die dreistufige Rip-Eskalation (normal → gedrosselt → ddrescue) wurde mit
Fake-`makemkvcon`/`ddrescue`-Skripten end-to-end verifiziert, aber nie an
einer echten, tatsächlich stark beschädigten Disc über die volle Laufzeit
(Timeouts von 4+5 Minuten vor ddrescue-Start) durchlaufen.

## Keine automatisierten Tests für die Rip-/Encode-Steuerlogik selbst

**Priorität: niedrig**

`tests/run.sh` deckt die reinen, deterministischen Funktionen ab
(Namensschema, XML-Escaping, Textkürzung, Ähnlichkeitsheuristik). Die
zustandsbehaftete Logik in `makemkv_rip`/`rip_main_feature`/`encode_to_hevc`
(Hintergrundprozesse, Polling, Eskalation) ist nur durch die Ad-hoc-Tests mit
Fake-Tools während der Entwicklung abgedeckt, nicht durch eine dauerhafte
Testsuite. Wurde bewusst nicht formalisiert — der Aufwand für robuste
Fake-Tool-Fixtures stünde in keinem Verhältnis zum Nutzen bei einem Projekt
dieser Größe.
