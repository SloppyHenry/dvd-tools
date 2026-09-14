#!/usr/bin/env bash
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
  local pct="$1" label="${2:-}"
  [ -z "$pct" ] && return
  # Balkenbreite an die Terminalbreite anpassen: auf schmalen Terminals hat
  # der Nutzer mehr von Geschwindigkeit/Status als von einem breiten Balken.
  local term_width; term_width=$(term_cols)
  local width=20
  [ "$term_width" -lt 70 ] && width=10
  [ "$term_width" -lt 50 ] && width=6
  local filled=$(( ${pct%.*} * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
  local empty=$((width - filled))
  # Fixer Anteil: "  [" (3) + Balken + "] " (2) + Prozent (6) + "  " (2)
  # = 13 + width. Ein Zeichen Reserve, damit die Zeile nie exakt bis zur
  # letzten Spalte reicht (manche Terminals brechen dann schon um).
  local max_label=$(( term_width - width - 14 ))
  [ "$max_label" -lt 3 ] && max_label=3
  label="$(truncate_text "$label" "$max_label")"
  printf "\r\033[K  ${C_GREEN}["
  # "printf FMT" ohne Argumente laeuft das Format trotzdem einmal ab - bei
  # filled/empty = 0 gaebe das ein Zeichen zu viel, daher explizit pruefen.
  [ "$filled" -gt 0 ] && printf '%0.s#' $(seq 1 "$filled") 2>/dev/null
  printf "${C_RESET}${C_DIM}"
  [ "$empty" -gt 0 ] && printf '%0.s.' $(seq 1 "$empty") 2>/dev/null
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

