#!/usr/bin/env bash
# ---------- Fehlerbehandlung und Wiederherstellung beim Rippen ----------
# Trennt die beiden Fehlerbilder, die frueher in einen Topf geworfen wurden:
# ein Rip, der nie angelaufen ist (Konfiguration/Zugriff), und ein Rip, der
# an der Disc scheitert (Lesefehler). Nur Letzteres rechtfertigt die
# zeitaufwendige ddrescue-Eskalation.

# makemkv_longest_skipped_title LOG -> Laenge (Sekunden) des laengsten Titels,
# den MakeMKV wegen --minlength uebersprungen hat; leer, wenn keiner.
# Ausgewertet wird Meldungscode 3025 ueber seine numerischen Parameter
# (Feld 6 = Titellaenge in Sekunden) - der Klartext der Meldung ist
# lokalisiert und damit nicht verlaesslich auswertbar.
makemkv_longest_skipped_title() {
  [ -f "${1:-}" ] || return 0
  python3 -c '
import sys, csv
best = 0
for raw in sys.stdin:
    raw = raw.strip()
    if not raw.startswith("MSG:3025,"):
        continue
    try:
        best = max(best, int(next(csv.reader([raw[4:]]))[6]))
    except Exception:
        pass
print(best or "")
' < "$1" 2>/dev/null
}

# makemkv_error_lines LOG -> die letzten Fehlermeldungen im Klartext
# (Meldungscodes ab 5000), damit im Fehlerfall die echte Ursache sichtbar
# wird statt nur eines Rueckgabewerts.
makemkv_error_lines() {
  [ -f "${1:-}" ] || return 0
  python3 -c '
import sys, csv
out = []
for raw in sys.stdin:
    raw = raw.strip()
    if not raw.startswith("MSG:"):
        continue
    try:
        f = next(csv.reader([raw[4:]]))
    except Exception:
        continue
    if f[0].isdigit() and int(f[0]) >= 5000 and f[3]:
        out.append(" ".join(f[3].split()))
for line in dict.fromkeys(out[-4:]):
    print(line)
' < "$1" 2>/dev/null
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

  substep "ddrescue Durchlauf 1/2 (schnell, ueberspringt kaputte Stellen)..."
  ddrescue -n -b 2048 "$drive" "$iso" "$mapfile"

  substep "ddrescue Durchlauf 2/2 (gezielte Retries nur auf den kaputten Stellen - kann dauern)..."
  ddrescue -d -r3 -b 2048 "$drive" "$iso" "$mapfile"

  if command -v ddrescuelog >/dev/null 2>&1; then
    info "ddrescue-Zusammenfassung:"
    ddrescuelog -t "$mapfile" 2>/dev/null | sed 's/^/  /'
  fi

  [ -s "$iso" ]
}

# rip_main_feature MK_INDEX DRIVE RIP_DIR -> rippt den Hauptfilm.
#
# Schlaegt der erste Versuch fehl, wird zuerst unterschieden, WARUM:
#   a) Der Rip hat nie angefangen (kein einziges Byte geschrieben und kein
#      Haenger-Timeout). Das ist kein Lesefehler - eskalieren waere hier
#      reine Zeitverschwendung und wuerde die echte Ursache verschleiern.
#      Haeufigster Fall: MakeMKV hat jeden Titel wegen --minlength
#      uebersprungen (Serien-/Episoden-DVD). Dann wird das benannt und ein
#      passender Wert angeboten. Sonst werden MakeMKVs Fehlermeldungen
#      ausgegeben und abgebrochen.
#   b) Der Rip blieb haengen (Rueckgabe 124) oder brach nach Teildaten ab.
#      Erst dann greift die dreistufige Eskalation:
#        1. normale Geschwindigkeit  2. gedrosselt (4x)  3. ddrescue-Image
#
# Rueckgabewert 0 bei Erfolg, ungleich 0 sonst.
rip_main_feature() {
  local mk_index="$1" drive="$2" rip_dir="$3" rc written

  makemkv_rip "disc:$mk_index" "$rip_dir" 240 "$drive"
  rc=$?
  [ "$rc" -eq 0 ] && return 0

  written="$(dir_size_bytes "$rip_dir")"; written="${written:-0}"
  if [ "$rc" -ne 124 ] && [ "$written" -eq 0 ]; then
    rip_handle_failed_start "$mk_index" "$drive" "$rip_dir"
    return $?
  fi

  warn "Rippen haengt oder brach mit Teildaten ab (vermutlich Lesefehler)."
  rm -f "$MAKEMKV_LAST_LOG"

  if is_macos; then
    info "Geschwindigkeitsdrosselung gibt es unter macOS nicht - ueberspringe diese Stufe."
  else
    warn "Versuche mit gedrosselter Geschwindigkeit (4x)..."
    find "$rip_dir" -mindepth 1 -delete 2>/dev/null
    set_drive_speed "$drive" 4
    sleep 2

    if makemkv_rip "disc:$mk_index" "$rip_dir" 300 "$drive"; then
      ok "Rip bei gedrosselter Geschwindigkeit erfolgreich."
      set_drive_speed "$drive" 0
      return 0
    fi
    set_drive_speed "$drive" 0
    rm -f "$MAKEMKV_LAST_LOG"
  fi
  warn "Weiterhin Leseprobleme - wechsle auf ddrescue-Imaging."
  warn "Das kann bei stark beschaedigten Discs deutlich laenger dauern (im Extremfall Stunden statt Minuten)."
  find "$rip_dir" -mindepth 1 -delete 2>/dev/null

  local iso; iso="$(dirname "$rip_dir")/rescue.iso"
  if ! rescue_image_disc "$drive" "$iso"; then
    err "ddrescue konnte kein brauchbares Disc-Image erstellen."
    return 1
  fi
  ok "Disc-Image erstellt ($(human_bytes "$(file_size_bytes "$iso")")), rippe nun aus dem Image..."

  makemkv_rip "iso:$iso" "$rip_dir" 0
}

# rip_handle_failed_start MK_INDEX DRIVE RIP_DIR -> behandelt einen Rip, der
# gar nicht erst angelaufen ist. Siehe rip_main_feature, Fall (a).
rip_handle_failed_start() {
  local mk_index="$1" drive="$2" rip_dir="$3"
  local log="$MAKEMKV_LAST_LOG" skipped suggest rc

  skipped="$(makemkv_longest_skipped_title "$log")"
  if [ -n "$skipped" ]; then
    warn "MakeMKV hat jeden Titel der Disc uebersprungen."
    info "Der laengste Titel ist ${skipped}s lang, die eingestellte Mindestlaenge"
    info "betraegt ${DVD_TOOLS_MIN_TITLE_SECONDS}s. Das ist kein Lesefehler - typisch"
    info "fuer Serien-/Episoden-DVDs mit kurzen Einzelfolgen."
    # Etwas unter den laengsten gefundenen Titel, damit gleich lange
    # Geschwister-Titel mit erfasst werden.
    suggest=$(( skipped > 60 ? skipped - 60 : 30 ))
    echo
    if confirm "Erneut mit Mindestlaenge ${suggest}s versuchen (rippt dann alle Folgen)?"; then
      rm -f "$log"
      local saved="$DVD_TOOLS_MIN_TITLE_SECONDS"
      DVD_TOOLS_MIN_TITLE_SECONDS="$suggest"
      makemkv_rip "disc:$mk_index" "$rip_dir" 240 "$drive"
      rc=$?
      DVD_TOOLS_MIN_TITLE_SECONDS="$saved"
      [ "$rc" -eq 0 ] && return 0
      err "Auch mit ${suggest}s Mindestlaenge kein Erfolg."
    fi
    info "Dauerhaft einstellbar ueber DVD_TOOLS_MIN_TITLE_SECONDS in"
    info "\$HOME/.config/dvd-tools/config."
    rm -f "$MAKEMKV_LAST_LOG"
    return 1
  fi

  err "MakeMKV konnte den Rip nicht starten (keine Daten geschrieben)."
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && info "MakeMKV: $line"
  done < <(makemkv_error_lines "$log")
  info "Haeufige Ursachen: Laufwerk von einem anderen Programm belegt"
  info "(MakeMKV-GUI, gemountete Disc), fehlende Leserechte auf $drive,"
  info "oder eine Disc, die MakeMKV nicht unterstuetzt."
  rm -f "$log"
  return 1
}
