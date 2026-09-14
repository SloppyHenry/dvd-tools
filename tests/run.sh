#!/usr/bin/env bash
# Regressionstests fuer die riskantesten reinen Funktionen in common.sh
# (Namensschema, XML-Escaping, Text-Kuerzung, Aehnlichkeits-Heuristik).
# Keine externe Testframework-Abhaengigkeit, keine echte Disc/kein Encoding
# noetig - reine Logikpruefung. Fuer die Rip-/Encode-Steuerlogik siehe die
# Fake-Tool-Beispiele weiter unten in dieser Datei.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0")")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/dvd-tools/common.sh
source "$ROOT_DIR/lib/dvd-tools/common.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  ok  - $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL - $desc"
    echo "        erwartet: $expected"
    echo "        erhalten: $actual"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  ok  - $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL - $desc"
    echo "        sollte enthalten: $needle"
    echo "        erhalten:         $haystack"
  fi
}

echo "== build_basename =="
assert_eq "Titel + Jahr + TMDB-ID" \
  "Ziemlich beste Freunde (2011) [tmdbid-77338]" \
  "$(build_basename "Ziemlich beste Freunde" "2011" "77338")"
assert_eq "nur Titel" \
  "Ohne Jahr" \
  "$(build_basename "Ohne Jahr" "" "")"
assert_eq "problematische Pfadzeichen werden durch Leerzeichen ersetzt (nicht geloescht)" \
  "Titel mit bösen Zeichen" \
  "$(build_basename 'Titel: mit/bösen "Zeichen"?' "" "")"
assert_eq "AC/DC verschmilzt nicht zu ACDC" \
  "AC DC Live" \
  "$(build_basename "AC/DC Live" "" "")"

echo "== xml_escape / write_tags_xml =="
assert_eq "Et-Zeichen wird escaped" "Fast &amp; Furious" "$(xml_escape "Fast & Furious")"
assert_eq "spitze Klammern werden escaped" "&lt;Cut&gt;" "$(xml_escape "<Cut>")"
TAGFILE="$(mktemp --suffix=.xml)"
write_tags_xml 'Fast & Furious <Extended> "Cut"' "2003" "$TAGFILE"
if python3 -c "import xml.etree.ElementTree as ET; ET.parse('$TAGFILE')" 2>/dev/null; then
  PASS=$((PASS + 1)); echo "  ok  - erzeugte Tags-XML ist wohlgeformt (Titel mit &, <, >, \")"
else
  FAIL=$((FAIL + 1)); echo "  FAIL - erzeugte Tags-XML ist NICHT wohlgeformt"
fi
rm -f "$TAGFILE"

echo "== clean_disc_label =="
assert_eq "Unterstriche/Punkte werden zu Leerzeichen, GROSS zu Title-Case" \
  "Star Wars 1977" \
  "$(clean_disc_label "STAR.WARS_1977")"
assert_eq "gemischte Schreibweise bleibt unangetastet" \
  "Bereits Gemischt" \
  "$(clean_disc_label "Bereits Gemischt")"

echo "== similarity =="
assert_eq "identischer Text -> 1.000" "1.000" "$(similarity "The Green Mile" "The Green Mile")"
S="$(similarity "B1 T00" "The Green Mile")"
if awk -v s="$S" 'BEGIN{exit !(s < 0.3)}'; then
  PASS=$((PASS + 1)); echo "  ok  - unaehnlicher Text -> niedrige Aehnlichkeit ($S)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL - unaehnlicher Text ergab zu hohe Aehnlichkeit: $S"
fi

echo "== truncate_text =="
assert_eq "kuerzerer Text bleibt unveraendert" "kurz" "$(truncate_text "kurz" 10)"
assert_eq "laengerer Text wird auf MAXLEN inkl. Ellipse gekuerzt" \
  "1234…" "$(truncate_text "123456789" 5)"

echo "== progress_bar / spinner_line ueberschreiten nie die Terminalbreite =="
LONG="Rippen (MakeMKV) — 1 Titel werden in Verzeichnis file:///tmp/dvd-auto.vpOkIm/rip gespeichert   30.7 MB/s (~23.2x)"
for cols in 40 80 120; do
  tput() { [ "$1" = "cols" ] && echo "$cols" || command tput "$@" 2>/dev/null; }
  LEN=$(progress_bar 42.5 "$LONG" 2>/dev/null | sed -r 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' \
          | python3 -c 'import sys; print(len(sys.stdin.read().rstrip("\n")))')
  if [ "$LEN" -le "$cols" ]; then
    PASS=$((PASS + 1)); echo "  ok  - progress_bar bei $cols Spalten passt ($LEN Zeichen)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - progress_bar bei $cols Spalten zu lang: $LEN Zeichen"
  fi
  unset -f tput
done

# Der eigentliche Anzeigefehler war nicht die Ueberlaenge, sondern die
# Reihenfolge: der variable MakeMKV-Statustext stand vor den Zahlen und hat
# beim Kappen zuerst die Lesegeschwindigkeit gefressen ("2.7 MB/…").
# Darum: Zahlen zuerst, Status zuletzt - hier abgesichert.
echo "== Lesegeschwindigkeit ueberlebt das Kappen =="
for cols in 60 80; do
  tput() { [ "$1" = "cols" ] && echo "$cols" || command tput "$@" 2>/dev/null; }
  LABEL="$(printf '%8s' "$(human_bytes 1932735283)") $(printf '%6.1f MB/s ~%4.1fx' 30.7 23.2)  1 Titel werden in Verzeichnis … gespeichert"
  OUT=$(progress_bar 42.5 "$LABEL" 2>/dev/null | sed -r 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r')
  assert_contains "bei $cols Spalten bleibt MB/s + x-Faktor vollstaendig" "30.7 MB/s ~23.2x" "$OUT"
  assert_contains "bei $cols Spalten bleibt die geschriebene Datenmenge" "1.8 GB" "$OUT"
  unset -f tput
done

echo "== latest_status entfernt file://-Pfade =="
STATUS_LOG="$(mktemp)"
printf 'MSG:1005,0,1,"Saving 1 titles into directory file:///home/henry/Filme/.tmp/rip","%%1","x"\n' > "$STATUS_LOG"
assert_eq "voller Pfad wird durch Ellipse ersetzt" \
  "Saving 1 titles into directory …" "$(latest_status "$STATUS_LOG")"
rm -f "$STATUS_LOG"

echo "== label_is_generic =="
for l in "DVD_VIDEO" "B1_T00" "LOGICAL_VOLUME_ID" "UNTITLED" "12345" "X"; do
  if label_is_generic "$l"; then
    PASS=$((PASS + 1)); echo "  ok  - \"$l\" gilt als nichtssagend"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - \"$l\" haette als nichtssagend gelten muessen"
  fi
done
for l in "THE_GREEN_MILE" "ZIEMLICH_BESTE_FREUNDE" "DAS.LEBEN.DES.BRIAN"; do
  if label_is_generic "$l"; then
    FAIL=$((FAIL + 1)); echo "  FAIL - \"$l\" faelschlich als nichtssagend eingestuft"
  else
    PASS=$((PASS + 1)); echo "  ok  - \"$l\" wird gesucht"
  fi
done

# Die Anbieterwahl wird mit gefaelschten Suchfunktionen geprueft, damit die
# Tests ohne Netzwerk laufen (CI hat keinen garantierten Zugang und die
# Fremd-APIs sollen nicht bei jedem Commit angefragt werden).
echo "== movie_search waehlt den richtigen Anbieter =="
tmdb_search()     { [ -n "$FAKE_TMDB" ] && printf '%s\n' "$FAKE_TMDB"; }
wikidata_search() { [ -n "$FAKE_WIKIDATA" ] && printf '%s\n' "$FAKE_WIKIDATA"; }
FAKE_TMDB=""; FAKE_WIKIDATA=""

FAKE_TMDB="$(printf '497\tThe Green Mile\t1999\t')"
FAKE_WIKIDATA="$(printf '497\tThe Green Mile\t1999\t189')"
TMDB_API_KEY="dummy" DVD_TOOLS_METADATA_PROVIDER=auto movie_search "x"
assert_eq "mit Key wird TMDB bevorzugt" "TMDB" "$MOVIE_SEARCH_PROVIDER"

TMDB_API_KEY="" DVD_TOOLS_METADATA_PROVIDER=auto movie_search "x"
assert_eq "ohne Key wird Wikidata benutzt" "Wikidata" "$MOVIE_SEARCH_PROVIDER"
assert_eq "Wikidata-Zeile enthaelt die Laufzeit" "189" "$(cut -f4 <<<"${MOVIE_CANDIDATES[0]}")"

FAKE_TMDB=""
TMDB_API_KEY="dummy" DVD_TOOLS_METADATA_PROVIDER=auto movie_search "x"
assert_eq "leeres TMDB-Ergebnis faellt auf Wikidata zurueck" "Wikidata" "$MOVIE_SEARCH_PROVIDER"

FAKE_WIKIDATA=""
if TMDB_API_KEY="" DVD_TOOLS_METADATA_PROVIDER=auto movie_search "x"; then
  FAIL=$((FAIL + 1)); echo "  FAIL - movie_search haette ohne Treffer fehlschlagen muessen"
else
  PASS=$((PASS + 1)); echo "  ok  - ohne Treffer Rueckgabewert ungleich 0"
fi

FAKE_WIKIDATA="$(printf '1\tEgal\t2000\t90')"
if DVD_TOOLS_METADATA_PROVIDER=off movie_search "x"; then
  FAIL=$((FAIL + 1)); echo "  FAIL - Anbieter \"off\" haette nicht suchen duerfen"
else
  PASS=$((PASS + 1)); echo "  ok  - Anbieter \"off\" schaltet die Suche ab"
fi
unset -f tmdb_search wikidata_search

echo
echo "== Ergebnis: $PASS bestanden, $FAIL fehlgeschlagen =="
[ "$FAIL" -eq 0 ]
