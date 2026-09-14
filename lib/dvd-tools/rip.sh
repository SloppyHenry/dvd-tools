#!/usr/bin/env bash
# ---------- MakeMKV-Rip mit Live-Fortschritt (Prozent, MB/s, x-Faktor) ----------
# Echte Laufwerks-RPM lassen sich unter Linux nicht ueber eine Standard-API
# auslesen (kein Kernel-Interface dafuer) - stattdessen wird die uebliche
# Kennzahl der optischen-Medien-Welt verwendet: der x-Faktor, berechnet aus
# der tatsaechlich gemessenen Lesegeschwindigkeit (1x DVD = 1.32 MB/s).
DVD_1X_BYTES_PER_SEC=1384448

# Letzte lesbare Statuszeile aus dem robot-mode-Log (PRGC- oder MSG-Text).
latest_status() {
  local log="$1"
  tail -n 80 "$log" 2>/dev/null | python3 -c '
import sys, csv
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
# Lange MakeMKV-Meldungen (z.B. volle file://-Pfade) hart kappen, sonst
# ueberschreitet die Zeile die Terminalbreite, bricht um, und die
# "\r"-basierte Live-Anzeige zeichnet danach nur noch teilweise/kaputt neu.
if len(text) > 45:
    text = text[:44] + "…"
print(text)
' 2>/dev/null
}

# makemkv_rip SOURCE RIP_DIR [STALL_TIMEOUT] -> rippt mit Live-Anzeige.
# SOURCE ist alles, was makemkvcon als Quelle akzeptiert ("disc:N" oder
# "iso:/pfad/zur.iso"). STALL_TIMEOUT (Sekunden ohne jeglichen Datenzuwachs,
# 0 = kein Limit) bricht bei vermuteten Lesefehlern kontrolliert ab statt
# endlos zu haengen (Rueckgabe 124, wie bei timeout(1)).
# Zeigt IMMER etwas an (Spinner+Status+Speed sobald Daten fliessen),
# unabhaengig davon, ob MakeMKV ueberhaupt PRGV-Prozentzeilen liefert -
# manche Versionen tun das beim "mkv"-Befehl nicht.
makemkv_rip() {
  local source="$1" rip_dir="$2" stall_timeout="${3:-0}"
  local log; log="$(mktemp)"
  run_unbuffered makemkvcon -r --minlength=1200 mkv "$source" all "$rip_dir" \
    > "$log" 2>&1 &
  local pid=$!

  local prev_bytes=0 prev_time cur_bytes cur_time dt db mbs xf pct_line pct status label stalled_for=0
  prev_time=$(now_seconds)
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    cur_bytes="$(dir_size_bytes "$rip_dir")"
    cur_bytes="${cur_bytes:-0}"
    cur_time=$(now_seconds)
    dt=$(awk -v a="$cur_time" -v b="$prev_time" 'BEGIN{print a-b}')
    db=$((cur_bytes - prev_bytes))
    read -r mbs xf <<<"$(awk -v b="$db" -v t="$dt" -v c="$DVD_1X_BYTES_PER_SEC" 'BEGIN{
      mb = (t > 0 && b > 0) ? b/t/1048576 : 0
      x  = (t > 0 && b > 0) ? b/t/c : 0
      printf "%.1f %.1f", mb, x
    }')"

    if [ "$db" -le 0 ]; then
      stalled_for=$((stalled_for + 1))
    else
      stalled_for=0
    fi
    if [ "$stall_timeout" -gt 0 ] && [ "$stalled_for" -ge "$stall_timeout" ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      progress_done
      rm -f "$log"
      return 124
    fi

    status="$(latest_status "$log")"

    pct=""
    pct_line="$(grep -o 'PRGV:[0-9]*,[0-9]*,[0-9]*' "$log" | tail -1)"
    if [ -n "$pct_line" ]; then
      IFS=',' read -r _ total max <<<"${pct_line#PRGV:}"
      if [[ "$max" =~ ^[0-9]+$ ]] && [ "$max" -gt 0 ]; then
        pct=$(awk -v t="$total" -v m="$max" 'BEGIN{printf "%.1f", t*100/m}')
      fi
    fi

    label="Rippen (MakeMKV)"
    [ -n "$status" ] && label="$label — $status"
    if awk -v m="$mbs" 'BEGIN{exit !(m+0>0)}'; then
      label="$label  ${mbs} MB/s (~${xf}x)"
    fi

    if [ -n "$pct" ]; then
      progress_bar "$pct" "$label"
    else
      spinner_line "$label"
    fi

    prev_bytes=$cur_bytes
    prev_time=$cur_time
  done
  progress_done

  wait "$pid"
  local rc=$?
  rm -f "$log"
  return $rc
}

# set_drive_speed DEVICE SPEED_X -> drosselt die Laufwerksgeschwindigkeit
# (best effort, manche Laufwerke/Kernel unterstuetzen das nicht - dann wird
# einfach ignoriert, kein harter Fehler).
set_drive_speed() {
  local drive="$1" speed="$2"
  # Unter macOS gibt es kein Aequivalent zu "eject -x" (Laufwerks-
  # Geschwindigkeit drosseln) - rip_main_feature ueberspringt die
  # entsprechende Eskalationsstufe dort daher komplett.
  is_macos && return 1
  eject -x "$speed" "$drive" >/dev/null 2>&1
}

# rescue_image_disc DEVICE ISO_PATH -> zweistufiges ddrescue-Imaging
# (1. schnell, ueberspringt kaputte Stellen  2. gezielte Retries nur auf
# den kaputten Stellen). Laesst ddrescues eigene, dafuer gebaute
# Live-Anzeige direkt durch (nicht selbst nachgebaut). Kann bei stark
# beschaedigten Discs deutlich laenger dauern als ein normaler Rip.
rescue_image_disc() {
  local drive="$1" iso="$2"
  local mapfile="${iso}.map"
  need ddrescue

  step "ddrescue Durchlauf 1/2 (schnell, ueberspringt kaputte Stellen)..."
  ddrescue -n -b 2048 "$drive" "$iso" "$mapfile"

  step "ddrescue Durchlauf 2/2 (gezielte Retries nur auf den kaputten Stellen - kann dauern)..."
  ddrescue -d -r3 -b 2048 "$drive" "$iso" "$mapfile"

  if command -v ddrescuelog >/dev/null 2>&1; then
    info "ddrescue-Zusammenfassung:"
    ddrescuelog -t "$mapfile" 2>/dev/null | sed 's/^/  /'
  fi

  [ -s "$iso" ]
}

# rip_main_feature MK_INDEX DRIVE RIP_DIR -> rippt mit dreistufiger
# Eskalation bei Lesefehlern/Haengern:
#   1. normale Geschwindigkeit
#   2. gedrosselte Geschwindigkeit (4x)
#   3. ddrescue-Image + Rip aus dem Image
# Rueckgabewert 0 bei Erfolg, ungleich 0 wenn alle Stufen fehlschlagen.
rip_main_feature() {
  local mk_index="$1" drive="$2" rip_dir="$3"

  if makemkv_rip "disc:$mk_index" "$rip_dir" 240; then
    return 0
  fi
  warn "Rippen haengt oder schlaegt fehl (vermutlich Lesefehler)."

  if is_macos; then
    info "Geschwindigkeitsdrosselung gibt es unter macOS nicht - ueberspringe diese Stufe."
  else
    warn "Versuche mit gedrosselter Geschwindigkeit (4x)..."
    find "$rip_dir" -mindepth 1 -delete 2>/dev/null
    set_drive_speed "$drive" 4
    sleep 2

    if makemkv_rip "disc:$mk_index" "$rip_dir" 300; then
      ok "Rip bei gedrosselter Geschwindigkeit erfolgreich."
      set_drive_speed "$drive" 0
      return 0
    fi
    set_drive_speed "$drive" 0
  fi
  warn "Weiterhin Leseprobleme - wechsle auf ddrescue-Imaging."
  warn "Das kann bei stark beschaedigten Discs deutlich laenger dauern (im Extremfall Stunden statt Minuten)."
  find "$rip_dir" -mindepth 1 -delete 2>/dev/null

  local iso; iso="$(dirname "$rip_dir")/rescue.iso"
  if ! rescue_image_disc "$drive" "$iso"; then
    err "ddrescue konnte kein brauchbares Disc-Image erstellen."
    return 1
  fi
  ok "Disc-Image erstellt ($(du -h "$iso" 2>/dev/null | cut -f1)), rippe nun aus dem Image..."

  makemkv_rip "iso:$iso" "$rip_dir" 0
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

