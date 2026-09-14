#!/usr/bin/env bash
# Gemeinsame Funktionen fuer dvd-shrink / dvd-auto.
# Wird per `source` eingebunden, kein eigenstaendiges Skript.

# printf mit "." als Dezimaltrennzeichen erzwingen (unabhaengig von der Systemlocale,
# sonst schlaegt z.B. printf %f mit "25.5" unter de_DE fehl).
export LC_NUMERIC=C

# Optionale Konfiguration (z.B. TMDB_API_KEY=...) aus ~/.config/dvd-tools/config laden.
DVD_TOOLS_CONFIG="${DVD_TOOLS_CONFIG:-$HOME/.config/dvd-tools/config}"
[ -f "$DVD_TOOLS_CONFIG" ] && source "$DVD_TOOLS_CONFIG"

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
progress_bar() {
  local pct="$1" label="${2:-}" width=32
  [ -z "$pct" ] && return
  local filled=$(( ${pct%.*} * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
  local empty=$((width - filled))
  printf "\r  ${C_GREEN}["
  printf '%0.s#' $(seq 1 "$filled") 2>/dev/null
  printf "${C_RESET}${C_DIM}"
  printf '%0.s.' $(seq 1 "$empty") 2>/dev/null
  printf "${C_RESET}] %5.1f%%  %-40s" "$pct" "$label"
}
progress_done() { echo; }

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
    -of json "$file" | python3 -c '
import json, sys

d = json.load(sys.stdin)
st = d["streams"][0]
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
'
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

# ---------- HandBrake-Encode mit huebschem Fortschrittsbalken ----------
# encode_to_hevc IN OUT QUALITY
encode_to_hevc() {
  local in="$1" out="$2" quality="$3"
  stdbuf -oL -eL HandBrakeCLI \
    -i "$in" \
    -o "$out" \
    -f av_mkv \
    -e nvenc_h265 \
    --encoder-preset slow \
    --encoder-profile main \
    -q "$quality" \
    --comb-detect --decomb \
    --auto-anamorphic \
    --all-audio --audio-lang-list any --aencoder copy --audio-fallback ac3 \
    --all-subtitles \
    -m 2>&1 | while IFS= read -r line; do
      if [[ "$line" =~ ([0-9]+\.[0-9]+)\ % ]]; then
        progress_bar "${BASH_REMATCH[1]}" "Encoding (NVENC)"
      fi
    done
  progress_done
}
