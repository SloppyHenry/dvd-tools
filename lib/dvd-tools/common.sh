#!/usr/bin/env bash
# Gemeinsame Funktionen fuer dvd-shrink / dvd-auto.
# Wird per `source` eingebunden, kein eigenstaendiges Skript.

# printf mit "." als Dezimaltrennzeichen erzwingen (unabhaengig von der Systemlocale,
# sonst schlaegt z.B. printf %f mit "25.5" unter de_DE fehl).
export LC_NUMERIC=C

# Optionale Konfiguration (z.B. TMDB_API_KEY=...) aus ~/.config/dvd-tools/config laden.
DVD_TOOLS_CONFIG="${DVD_TOOLS_CONFIG:-$HOME/.config/dvd-tools/config}"
[ -f "$DVD_TOOLS_CONFIG" ] && source "$DVD_TOOLS_CONFIG"

# ---------- Plattform-Abstraktion (Linux/Debian und macOS) ----------
# Alles hier kapselt Unterschiede zwischen GNU-Userland (Linux) und
# BSD-Userland (macOS): date/readlink/stat/du-Flags, eject, Encoder-Wahl.
DVD_TOOLS_OS="$(uname -s)"   # "Linux" oder "Darwin"

is_macos() { [ "$DVD_TOOLS_OS" = "Darwin" ]; }

# now_seconds -> Sekunden seit Epoch mit Nachkommastellen.
# "date +%s.%N" gibt es nur unter GNU/Linux (BSD-date auf macOS versteht
# %N nicht) - python3 ist ohnehin Pflichtabhaengigkeit, also darueber.
now_seconds() { python3 -c 'import time; print(time.time())'; }

# resolve_path PATH -> absoluter, aufgeloester Pfad (Ersatz fuer
# "readlink -f", das es unter macOS/BSD nicht gibt).
resolve_path() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

# file_size_bytes PATH -> Groesse in Bytes ("stat -c%s" ist GNU-spezifisch,
# BSD/macOS-stat braucht "-f%z").
file_size_bytes() {
  if is_macos; then
    stat -f%z "$1" 2>/dev/null || echo 0
  else
    stat -c%s "$1" 2>/dev/null || echo 0
  fi
}

# dir_size_bytes PATH -> Gesamtgroesse eines Verzeichnisses in Bytes
# ("du -sb" ist GNU-spezifisch, BSD-du kennt kein -b).
dir_size_bytes() {
  if is_macos; then
    du -sk "$1" 2>/dev/null | awk '{print $1*1024}'
  else
    du -sb "$1" 2>/dev/null | cut -f1
  fi
}

# cpu_count -> Anzahl CPU-Kerne ("nproc" gibt es unter macOS nicht).
cpu_count() {
  if is_macos; then
    sysctl -n hw.ncpu 2>/dev/null || echo 4
  else
    nproc 2>/dev/null || echo 4
  fi
}

# eject_disc DEVICE -> wirft die Disc aus (macOS: drutil/diskutil,
# Linux: eject).
eject_disc() {
  local drive="$1"
  if is_macos; then
    drutil eject "$drive" >/dev/null 2>&1 || diskutil eject "$drive" >/dev/null 2>&1
  else
    eject "$drive" >/dev/null 2>&1
  fi
}

# Liste der von der installierten HandBrakeCLI tatsaechlich unterstuetzten
# Video-Encoder (einmal pro Lauf ermittelt und gecacht). Wichtig: das ist
# die Quelle der Wahrheit dafuer, was waehlbar ist - nicht Plattform-
# Annahmen, denn nicht jeder HandBrake-Build hat QSV/VAAPI mit einkompiliert.
_HB_ENCODERS_CACHE=""
handbrake_encoders() {
  if [ -z "$_HB_ENCODERS_CACHE" ]; then
    _HB_ENCODERS_CACHE="$(HandBrakeCLI -h 2>/dev/null | awk '
      /--encoder <string>/ { f=1; next }
      f && /^\s+[a-zA-Z0-9_]+\s*$/ { gsub(/^[ \t]+|[ \t]+$/, ""); print; next }
      f && /^\s*$/ { exit }
      f && /^\s+-/ { exit }
    ')"
  fi
  printf '%s\n' "$_HB_ENCODERS_CACHE"
}

hb_has_encoder() { handbrake_encoders | grep -qx "$1"; }

# pick_hevc_encoder -> prueft live, welche GPU vorhanden ist und welche
# HEVC-Hardware-Encoder die installierte HandBrakeCLI dafuer tatsaechlich
# mitbringt (NVENC/NVIDIA, QSV/Intel, VCE/AMD, VideoToolbox/macOS) -
# faellt auf Software-x265 zurueck, wenn nichts Passendes gefunden wird.
pick_hevc_encoder() {
  if is_macos; then
    hb_has_encoder vt_h265 && { echo "vt_h265"; return; }
    echo "x265"
    return
  fi

  local gpu_info=""
  command -v lspci >/dev/null 2>&1 && gpu_info="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display')"

  if echo "$gpu_info" | grep -qi nvidia \
     && command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 \
     && hb_has_encoder nvenc_h265; then
    echo "nvenc_h265"; return
  fi
  if echo "$gpu_info" | grep -qi intel && hb_has_encoder qsv_h265; then
    echo "qsv_h265"; return
  fi
  if echo "$gpu_info" | grep -Eqi 'amd|ati|advanced micro devices' && hb_has_encoder vce_h265; then
    echo "vce_h265"; return
  fi
  # GPU-Erkennung war nicht eindeutig/erfolglos - trotzdem lieber irgendeinen
  # von HandBrake tatsaechlich angebotenen Hardware-Encoder nehmen, bevor
  # auf Software ausgewichen wird.
  local enc
  for enc in nvenc_h265 qsv_h265 vce_h265; do
    hb_has_encoder "$enc" && { echo "$enc"; return; }
  done
  echo "x265"
}

# ---------- Optik ----------
if [ -t 1 ]; then
  C_RESET=$(tput sgr0); C_BOLD=$(tput bold)
  C_GREEN=$(tput setaf 2); C_YELLOW=$(tput setaf 3)
  C_RED=$(tput setaf 1); C_CYAN=$(tput setaf 6); C_DIM=$(tput dim)
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_DIM=""
fi

hr() { printf '%s\n' "${C_DIM}$(printf '%.0s─' $(seq 1 "${1:-60}"))${C_RESET}"; }

header() {
  echo
  if command -v figlet >/dev/null 2>&1; then
    figlet -f small "$1" 2>/dev/null | sed "s/^/${C_CYAN}${C_BOLD}/;s/\$/${C_RESET}/"
  else
    echo "${C_CYAN}${C_BOLD}== $1 ==${C_RESET}"
  fi
  echo
}

step()  { echo "${C_CYAN}${C_BOLD}▶ $*${C_RESET}"; }
info()  { echo "${C_DIM}  $*${C_RESET}"; }
ok()    { echo "${C_GREEN}✔ $*${C_RESET}"; }
warn()  { echo "${C_YELLOW}⚠ $*${C_RESET}" >&2; }
err()   { echo "${C_RED}✘ $*${C_RESET}" >&2; }

# Einzeiliger Fortschrittsbalken. Nutzung: progress_bar 42 "Text"
# term_cols -> aktuelle Terminalbreite (Fallback 80, falls nicht ermittelbar).
term_cols() { tput cols 2>/dev/null || echo 80; }

# truncate_text TEXT MAXLEN -> kappt TEXT hart auf MAXLEN Zeichen (mit "…"),
# damit dynamische Live-Zeilen (Fortschrittsbalken/Spinner) nie die
# Terminalbreite ueberschreiten. Ohne Kappung bricht eine zu lange Zeile um
# und die "\r"-basierte Neuzeichnung zerstoert dann die Anzeige (Reste der
# vorherigen, umgebrochenen Zeile bleiben stehen -> "flackert und verschwindet").
truncate_text() {
  local text="$1" max="$2"
  [ "$max" -lt 1 ] && max=1
  if [ "${#text}" -gt "$max" ]; then
    echo "${text:0:$((max - 1))}…"
  else
    echo "$text"
  fi
}

progress_bar() {
  local pct="$1" label="${2:-}" width=20
  [ -z "$pct" ] && return
  local filled=$(( ${pct%.*} * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
  local empty=$((width - filled))
  # Fixer Anteil (Einrueckung, Balken, Prozent) ist ca. 45 Zeichen -
  # den Rest darf "label" maximal einnehmen, sonst wird gekappt.
  local max_label=$(( $(term_cols) - width - 15 ))
  [ "$max_label" -lt 3 ] && max_label=3
  label="$(truncate_text "$label" "$max_label")"
  printf "\r\033[K  ${C_GREEN}["
  printf '%0.s#' $(seq 1 "$filled") 2>/dev/null
  printf "${C_RESET}${C_DIM}"
  printf '%0.s.' $(seq 1 "$empty") 2>/dev/null
  printf "${C_RESET}] %5.1f%%  %s" "$pct" "$label"
}
progress_done() { echo; }

# Einzeiliger Spinner fuer Phasen ohne bekannten Prozentwert (z.B. Disc-Scan,
# oder wenn die zugrundeliegende Kennzahl - hier MakeMKV-PRGV - gar nicht
# geliefert wird). Nutzung: in einer Schleife wiederholt spinner_line "Text"
SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
SPINNER_I=0
spinner_line() {
  local text="${1:-Arbeite...}"
  local frame="${SPINNER_FRAMES[$((SPINNER_I % 10))]}"
  SPINNER_I=$((SPINNER_I + 1))
  local max_text=$(( $(term_cols) - 6 ))
  [ "$max_text" -lt 3 ] && max_text=3
  text="$(truncate_text "$text" "$max_text")"
  printf "\r\033[K  ${C_CYAN}%s${C_RESET} %s" "$frame" "$text"
}

need() {
  command -v "$1" >/dev/null 2>&1 || { err "'$1' ist nicht installiert."; exit 1; }
}

# ---------- Namensschema ----------
# build_basename TITLE YEAR TMDBID -> "Titel (Jahr) [tmdbid-ID]"
build_basename() {
  local title="$1" year="$2" tmdbid="$3" base="$1"
  [ -n "$year" ] && base="${base} (${year})"
  [ -n "$tmdbid" ] && base="${base} [tmdbid-${tmdbid}]"
  echo "$base" | tr -d '/\\:*?"<>|'
}

# write_tags_xml TITLE YEAR OUTFILE
write_tags_xml() {
  local title="$1" year="$2" outfile="$3"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE Tags SYSTEM "matroskatags.dtd">'
    echo '<Tags>'
    echo '  <Tag>'
    echo '    <Targets><TargetTypeValue>50</TargetTypeValue></Targets>'
    echo "    <Simple><Name>TITLE</Name><String>${title}</String></Simple>"
    if [ -n "$year" ]; then
      echo "    <Simple><Name>DATE_RELEASED</Name><String>${year}</String></Simple>"
    fi
    echo '  </Tag>'
    echo '</Tags>'
  } > "$outfile"
}

# tag_mkv FILE TITLE YEAR
tag_mkv() {
  local file="$1" title="$2" year="$3"
  local tagfile; tagfile=$(mktemp --suffix=.xml)
  write_tags_xml "$title" "$year" "$tagfile"
  mkvpropedit "$file" \
    --edit info --set "title=${title}" \
    --tags "all:${tagfile}" \
    --add-track-statistics-tags >/dev/null
  rm -f "$tagfile"
}

# ---------- Qualitaets-Heuristik ----------
# suggest_quality FILE -> "<cq>\t<info-text>"
suggest_quality() {
  local file="$1"
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height,avg_frame_rate,bit_rate:stream_tags=BPS:format=duration,size,bit_rate \
    -of json "$file" 2>/dev/null | python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
    st = d["streams"][0]
except Exception:
    sys.exit(1)
fmt = d.get("format", {})

width = int(st.get("width") or 0)
height = int(st.get("height") or 0)

fr = st.get("avg_frame_rate", "25/1")
try:
    num, den = fr.split("/")
    fps = float(num) / float(den) if float(den) else 25.0
except Exception:
    fps = 25.0

bitrate = st.get("bit_rate")
if not bitrate or bitrate == "N/A":
    bitrate = (st.get("tags") or {}).get("BPS")
if not bitrate or bitrate == "N/A":
    bitrate = fmt.get("bit_rate")
if not bitrate or bitrate == "N/A":
    size = float(fmt.get("size") or 0)
    duration = float(fmt.get("duration") or 0)
    bitrate = (size * 8 / duration) if duration else 0
bitrate = float(bitrate)

bpp = bitrate / (width * height * fps) if (width and height and fps) else 0

if bpp >= 0.35:
    cq, label = 17, "hoch (z.B. starkes Filmkorn)"
elif bpp >= 0.20:
    cq, label = 19, "mittel-hoch"
elif bpp >= 0.10:
    cq, label = 21, "mittel"
else:
    cq, label = 23, "niedrig (ruhige/animierte Quelle)"

if width >= 3800:
    cq += 3
elif width >= 1900:
    cq += 2
elif width >= 1280:
    cq += 1

info = (
    f"{width}x{height}, {fps:.2f} fps, Quellbitrate ~{bitrate/1000:.0f} kbit/s, "
    f"Komplexitaet: {label} (bpp={bpp:.3f})"
)
print(f"{cq}\t{info}")
' 2>/dev/null
}

# ---------- Titelerkennung anhand des Disc-Labels ----------

# clean_disc_label LABEL -> aufgeraeumter Titel-Vorschlag ("STAR_WARS.1977" -> "Star Wars 1977")
clean_disc_label() {
  local label="$1"
  echo "$label" | tr '_.' '  ' | python3 -c "
import sys
s = sys.stdin.read().strip()
# Durchgehend grossgeschriebene Labels (typisch fuer DVDs) in Titel-Case wandeln,
# gemischte Schreibweise (z.B. schon 'Star Wars') unangetastet lassen.
print(s.title() if s.isupper() else s)
"
}

# tmdb_search QUERY -> Zeilen "id\ttitle\tyear", leer wenn kein TMDB_API_KEY gesetzt ist
tmdb_search() {
  local query="$1"
  [ -z "${TMDB_API_KEY:-}" ] && return 1
  curl -fsS --get "https://api.themoviedb.org/3/search/movie" \
    --data-urlencode "api_key=$TMDB_API_KEY" \
    --data-urlencode "query=$query" \
    --data-urlencode "language=de-DE" 2>/dev/null \
  | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for r in d.get("results", [])[:8]:
    year = (r.get("release_date") or "")[:4]
    title = (r.get("title") or "").replace("\t", " ")
    mid = r["id"]
    print(f"{mid}\t{title}\t{year}")
'
}

# similarity A B -> Aehnlichkeit 0.000-1.000
similarity() {
  python3 - "$1" "$2" <<'PY'
import sys, difflib
a, b = sys.argv[1].lower(), sys.argv[2].lower()
print(f"{difflib.SequenceMatcher(None, a, b).ratio():.3f}")
PY
}

# identify_from_label LABEL -> fragt bei Bedarf interaktiv nach, setzt danach
# die globalen Variablen TITLE, YEAR, TMDBID.
identify_from_label() {
  local label="$1"
  local guess; guess="$(clean_disc_label "$label")"
  TITLE=""; YEAR=""; TMDBID=""

  if [ -z "${TMDB_API_KEY:-}" ]; then
    warn "Keine TMDB_API_KEY gesetzt (siehe README) - automatische Erkennung uebersprungen."
    read -rp "Filmtitel (Vorschlag: '$guess'): " TITLE
    TITLE="${TITLE:-$guess}"
    read -rp "Erscheinungsjahr (optional): " YEAR
    read -rp "TMDB-ID (optional): " TMDBID
    return
  fi

  step "Suche \"$guess\" bei TMDB..."
  mapfile -t CANDIDATES < <(tmdb_search "$guess")

  if [ "${#CANDIDATES[@]}" -gt 0 ]; then
    local top_id top_title top_year sim
    top_id="$(cut -f1 <<<"${CANDIDATES[0]}")"
    top_title="$(cut -f2 <<<"${CANDIDATES[0]}")"
    top_year="$(cut -f3 <<<"${CANDIDATES[0]}")"
    sim="$(similarity "$guess" "$top_title")"

    if python3 -c "import sys; sys.exit(0 if float('$sim') >= 0.72 else 1)"; then
      ok "Erkannt: $top_title ($top_year) [tmdbid-$top_id]"
      read -rp "Uebernehmen? (J/n): " CONFIRM_GUESS
      if ! [[ "$CONFIRM_GUESS" =~ ^[nN]$ ]]; then
        TITLE="$top_title"; YEAR="$top_year"; TMDBID="$top_id"
        return
      fi
    fi
  fi

  if [ "${#CANDIDATES[@]}" -gt 0 ]; then
    echo "Unsicher - mehrere moegliche Treffer fuer \"$guess\":"
    for i in "${!CANDIDATES[@]}"; do
      printf "  [%d] %s (%s)\n" "$((i+1))" "$(cut -f2 <<<"${CANDIDATES[$i]}")" "$(cut -f3 <<<"${CANDIDATES[$i]}")"
    done
    echo "  [0] Manuell eingeben"
    read -rp "Auswahl: " PICK
    if [[ "$PICK" =~ ^[0-9]+$ ]] && [ "$PICK" -ge 1 ] && [ "$PICK" -le "${#CANDIDATES[@]}" ]; then
      local row="${CANDIDATES[$((PICK-1))]}"
      TMDBID="$(cut -f1 <<<"$row")"; TITLE="$(cut -f2 <<<"$row")"; YEAR="$(cut -f3 <<<"$row")"
      return
    fi
  else
    warn "Keine TMDB-Treffer fuer \"$guess\"."
  fi

  read -rp "Filmtitel (Vorschlag: '$guess'): " TITLE
  TITLE="${TITLE:-$guess}"
  read -rp "Erscheinungsjahr (optional): " YEAR
  read -rp "TMDB-ID (optional): " TMDBID
}

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

# ---------- HandBrake-Encode mit huebschem Fortschrittsbalken ----------
# encode_to_hevc IN OUT QUALITY
encode_to_hevc() {
  local in="$1" out="$2" quality="$3"
  local encoder; encoder="$(pick_hevc_encoder)"
  local extra=()
  case "$encoder" in
    nvenc_h265|x265) extra=(--encoder-preset slow --encoder-profile main) ;;
    # qsv_h265/vce_h265/vt_h265: eigene, abweichende Preset-Systeme (bei QSV
    # z.B. "speed"/"balanced"/"quality" statt "slow") - nicht verifizierbar
    # ohne passende Hardware, daher HandBrake-Standardwerte verwenden statt
    # einen moeglicherweise falschen Wert zu raten.
    *) extra=() ;;
  esac

  run_unbuffered HandBrakeCLI \
    -i "$in" \
    -o "$out" \
    -f av_mkv \
    -e "$encoder" \
    "${extra[@]}" \
    -q "$quality" \
    --comb-detect --decomb \
    --auto-anamorphic \
    --all-audio --audio-lang-list any --aencoder copy --audio-fallback ac3 \
    --all-subtitles \
    -m 2>&1 | while IFS= read -r line; do
      if [[ "$line" =~ ([0-9]+\.[0-9]+)\ %(\ \(([0-9.]+)\ fps,\ avg\ ([0-9.]+)\ fps,\ ETA\ ([0-9hms]+)\))? ]]; then
        pct="${BASH_REMATCH[1]}"
        if [ -n "${BASH_REMATCH[3]:-}" ]; then
          detail="Encoding (${encoder})  ${BASH_REMATCH[3]} fps (avg ${BASH_REMATCH[4]})  ETA ${BASH_REMATCH[5]}"
        else
          detail="Encoding (${encoder})"
        fi
        progress_bar "$pct" "$detail"
      fi
    done
  progress_done
}
