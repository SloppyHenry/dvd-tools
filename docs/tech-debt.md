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

## Kein Rate-Limit-Handling bei den Filmdatenbanken

**Priorität: niedrig**

Weder `tmdb_search` noch `wikidata_search` behandeln HTTP-429-Antworten
(Rate Limit) gesondert — ein fehlgeschlagener Request führt einfach zum
nächsten Anbieter bzw. zur manuellen Eingabe. Für die erwartete Nutzung
(ein Nutzer, ein paar Anfragen pro Tag) unkritisch; Wikimedia bittet bei
automatisierten Zugriffen um einen aussagekräftigen User-Agent, den setzt
`DVD_TOOLS_USER_AGENT` bereits.

## Laufzeit wird angezeigt, aber nicht automatisch abgeglichen

**Priorität: niedrig**

Wikidata liefert zu jedem Treffer die Laufzeit mit, und in der
Kandidatenliste hilft sie dem Nutzer beim Unterscheiden (Hauptfilm vs.
Kurzfilm vs. Dokumentation). Automatisch gegen die tatsächliche Länge des
Titels auf der Disc geprüft wird sie nicht — dafür müsste `dvd-auto` vor
dem Rippen ein `makemkvcon -r info` laufen lassen, was einen zusätzlichen
Disc-Scan von etwa einer Minute kostet. Das wäre der nächste sinnvolle
Ausbau, falls sich Fehlerkennungen häufen.

## Wikidata-Abdeckung ist nicht überall gleich gut

**Priorität: niedrig**

Bei Kinofilmen ist Wikidata sehr vollständig (inklusive TMDB-ID). Bei sehr
alten, regionalen oder direkt auf Video veröffentlichten Titeln fehlen
teilweise die TMDB-ID (P4947) oder das Erscheinungsjahr (P577) — dann
bleibt der entsprechende Teil des Ordnernamens einfach leer, was das
Namensschema bereits vorsieht. Wer die dichtere Datenbasis braucht, trägt
einen TMDB-Key ein.

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

## Fortschritt in Prozent ist beim Rippen nur eine Schätzung

**Priorität: niedrig**

Liefert MakeMKV keine `PRGV`-Zeilen (bei 1.18.4 beim `mkv`-Befehl der Fall),
schätzt `makemkv_rip` den Prozentwert aus dem Datenzuwachs im Zielverzeichnis
gegen die Rohgröße der Disc (`blockdev --getsize64`) bzw. des ISO-Images.
Gerippt werden aber nur Titel ab `--minlength=1200`, also nicht Menüs,
Trailer und kurze Extras — der Balken bleibt am Ende deshalb unter 100 % und
wird bei 99 % gedeckelt. Exakt wäre er nur mit einem vorgeschalteten
`makemkvcon -r info`-Scan, der pro Lauf zusätzliche Disc-Zeit kostet; das
wäre den Gewinn an Genauigkeit nicht wert. Unter macOS gibt es kein
`blockdev`-Äquivalent, dort läuft bei `disc:`-Quellen weiterhin der Spinner.
