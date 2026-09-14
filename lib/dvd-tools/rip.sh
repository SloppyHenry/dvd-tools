#!/usr/bin/env bash
# ---------- MakeMKV-Rip mit Live-Fortschritt (Prozent, MB/s, x-Faktor) ----------
# Echte Laufwerks-RPM lassen sich unter Linux nicht ueber eine Standard-API
# auslesen (kein Kernel-Interface dafuer) - stattdessen wird die uebliche
# Kennzahl der optischen-Medien-Welt verwendet: der x-Faktor, berechnet aus
# der tatsaechlich gemessenen Lesegeschwindigkeit (1x DVD = 1.32 MB/s).
DVD_1X_BYTES_PER_SEC=1384448

# Titel unterhalb dieser Laenge ueberspringt MakeMKV (Menues, Trailer,
# Logos). 20 Minuten passen fuer Spielfilme; Serien-/Episoden-DVDs haben
# aber oft nur 3-5 Minuten lange Titel und blieben damit komplett leer -
# rip_main_feature erkennt diesen Fall und bietet einen kleineren Wert an.
DVD_TOOLS_MIN_TITLE_SECONDS="${DVD_TOOLS_MIN_TITLE_SECONDS:-1200}"

# Letzte lesbare Statuszeile aus dem robot-mode-Log (PRGC- oder MSG-Text).
# Gibt den Text ungekappt zurueck - auf die Terminalbreite kappt erst die
# Anzeige selbst (progress_bar/spinner_line), damit die Zahlenspalten davor
# immer vollstaendig sichtbar bleiben.
latest_status() {
  local log="$1"
  tail -n 80 "$log" 2>/dev/null | python3 -c '
import sys, csv, re
text = ""
for raw in sys.stdin:
    raw = raw.strip()
    if raw.startswith("PRGC:"):
        try:
            f = next(csv.reader([raw[5:]]))
            if len(f) >= 3 and f[2]:
                text = f[2]
        except Exception:
            pass
    elif raw.startswith("MSG:"):
        try:
            f = next(csv.reader([raw[4:]]))
            if len(f) >= 4 and f[3]:
                text = f[3]
        except Exception:
            pass
# MakeMKV schreibt volle file://-Pfade in seine Meldungen. Die sagen dem
# Nutzer nichts, sind aber lang genug, um den Rest der Zeile zu verdraengen.
text = re.sub(r"file://\S*", "…", text)
print(" ".join(text.split()))
' 2>/dev/null
}

# expected_rip_bytes SOURCE [DEVICE] -> grobe Zielgroesse des Rips in Bytes,
# leer wenn nicht ermittelbar. Bei "iso:" die Dateigroesse, bei "disc:" die
# Datengroesse der eingelegten Disc (Linux: blockdev). Das ist bewusst nur
# eine Naeherung - gerippt werden nur Titel ab --minlength, Menues/Trailer
# fallen weg - deshalb wird der daraus berechnete Prozentwert bei 99 %
# gedeckelt und als "ca." ausgewiesen.
expected_rip_bytes() {
  local source="$1" dev="${2:-}"
  case "$source" in
    iso:*) file_size_bytes "${source#iso:}" ;;
    *)
      is_macos && return 0
      [ -b "$dev" ] && blockdev --getsize64 "$dev" 2>/dev/null
      ;;
  esac
}

# makemkv_rip SOURCE RIP_DIR [STALL_TIMEOUT] -> rippt mit Live-Anzeige.
# SOURCE ist alles, was makemkvcon als Quelle akzeptiert ("disc:N" oder
# "iso:/pfad/zur.iso"). STALL_TIMEOUT (Sekunden ohne jeglichen Datenzuwachs,
# 0 = kein Limit) bricht bei vermuteten Lesefehlern kontrolliert ab statt
# endlos zu haengen (Rueckgabe 124, wie bei timeout(1)).
# Zeigt IMMER etwas an (Spinner+Status+Speed sobald Daten fliessen),
# unabhaengig davon, ob MakeMKV ueberhaupt PRGV-Prozentzeilen liefert -
# manche Versionen tun das beim "mkv"-Befehl nicht.
# shellcheck disable=SC2034  # MAKEMKV_LAST_LOG wird von recover.sh ausgewertet
makemkv_rip() {
  local source="$1" rip_dir="$2" stall_timeout="${3:-0}" drive="${4:-}"
  local log; log="$(mktemp)"
  local expected; expected="$(expected_rip_bytes "$source" "$drive")"
  [[ "$expected" =~ ^[0-9]+$ ]] || expected=0
  run_unbuffered makemkvcon -r "--minlength=$DVD_TOOLS_MIN_TITLE_SECONDS" \
    mkv "$source" all "$rip_dir" \
    > "$log" 2>&1 &
  local pid=$!

  local prev_bytes=0 prev_time cur_bytes cur_time dt db mbs xf pct_line pct status label stalled_for=0
  # Geglaetteter Mittelwert: die Sekunden-Momentanwerte schwanken stark
  # (Laufwerks-Cache, Schreibpuffer), was die Anzeige sonst wild springen laesst.
  local avg_mbs=0 avg_xf=0
  prev_time=$(now_seconds)
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    cur_bytes="$(dir_size_bytes "$rip_dir")"
    cur_bytes="${cur_bytes:-0}"
    cur_time=$(now_seconds)
    dt=$(awk -v a="$cur_time" -v b="$prev_time" 'BEGIN{print a-b}')
    db=$((cur_bytes - prev_bytes))
    read -r mbs xf <<<"$(awk -v b="$db" -v t="$dt" -v c="$DVD_1X_BYTES_PER_SEC" \
                             -v am="$avg_mbs" -v ax="$avg_xf" 'BEGIN{
      mb = (t > 0 && b > 0) ? b/t/1048576 : 0
      x  = (t > 0 && b > 0) ? b/t/c : 0
      # exponentiell geglaettet (Gewicht 0.3 auf den neuen Messwert)
      mb = (am > 0) ? am + 0.3*(mb - am) : mb
      x  = (ax > 0) ? ax + 0.3*(x  - ax) : x
      printf "%.1f %.1f", mb, x
    }')"
    avg_mbs="$mbs"; avg_xf="$xf"

    if [ "$db" -le 0 ]; then
      stalled_for=$((stalled_for + 1))
    else
      stalled_for=0
    fi
    if [ "$stall_timeout" -gt 0 ] && [ "$stalled_for" -ge "$stall_timeout" ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      progress_done
      MAKEMKV_LAST_LOG="$log"
      return 124
    fi

    status="$(latest_status "$log")"

    # Fortschritt: bevorzugt MakeMKVs eigene PRGV-Zeilen. Die liefert aber
    # nicht jede MakeMKV-Version beim "mkv"-Befehl - dann wird ersatzweise
    # aus dem Datenzuwachs gegen die Disc-/ISO-Groesse geschaetzt.
    pct=""
    pct_line="$(grep -o 'PRGV:[0-9]*,[0-9]*,[0-9]*' "$log" | tail -1)"
    if [ -n "$pct_line" ]; then
      IFS=',' read -r _ total max <<<"${pct_line#PRGV:}"
      if [[ "$max" =~ ^[0-9]+$ ]] && [ "$max" -gt 0 ]; then
        pct=$(awk -v t="$total" -v m="$max" 'BEGIN{printf "%.1f", t*100/m}')
      fi
    fi
    if [ -z "$pct" ] && [ "$expected" -gt 0 ]; then
      pct=$(awk -v b="$cur_bytes" -v e="$expected" 'BEGIN{
        p = b*100/e; if (p > 99) p = 99; printf "%.1f", p
      }')
    fi

    # Feste Zahlenspalten ZUERST, variabler MakeMKV-Text ZULETZT: gekappt wird
    # immer von rechts, also faellt im Zweifel nur die Statusmeldung weg und
    # nie die Geschwindigkeit. Feste Feldbreiten verhindern ausserdem, dass
    # die Spalten jede Sekunde verspringen.
    label="$(printf '%8s' "$(human_bytes "$cur_bytes")")"
    if awk -v m="$mbs" 'BEGIN{exit !(m+0>0)}'; then
      label="$label $(printf '%6.1f MB/s ~%4.1fx' "$mbs" "$xf")"
    else
      label="$label $(printf '%18s' '')"
    fi
    [ -n "$status" ] && label="$label  $status"

    if [ -n "$pct" ]; then
      progress_bar "$pct" "$label"
    else
      spinner_line "Rippen  $label"
    fi

    prev_bytes=$cur_bytes
    prev_time=$cur_time
  done
  progress_done

  wait "$pid"
  local rc=$?
  # Bei Erfolg wird das Log nicht mehr gebraucht; im Fehlerfall bleibt es
  # liegen, damit der Aufrufer die MakeMKV-Meldungen auswerten und dem
  # Nutzer zeigen kann, statt nur "ging nicht" zu melden.
  MAKEMKV_LAST_LOG="$log"
  [ "$rc" -eq 0 ] && { rm -f "$log"; MAKEMKV_LAST_LOG=""; }
  return $rc
}

# run_unbuffered CMD... -> erzwingt Zeilenpufferung, sonst puffern
# makemkvcon/HandBrakeCLI beim Schreiben in eine Pipe blockweise und der
# Live-Fortschritt kommt verzoegert/gar nicht an. "stdbuf" ist GNU-
# coreutils-spezifisch (Linux); unter macOS gibt es das nur ueber
# Homebrew ("coreutils" -> gstdbuf, oder "expect" -> unbuffer). Ohne eines
# davon laeuft der Befehl normal (ggf. mit traegerer Live-Anzeige).
run_unbuffered() {
  if command -v stdbuf >/dev/null 2>&1; then
    stdbuf -oL -eL "$@"
  elif command -v gstdbuf >/dev/null 2>&1; then
    gstdbuf -oL -eL "$@"
  elif command -v unbuffer >/dev/null 2>&1; then
    unbuffer "$@"
  else
    "$@"
  fi
}

