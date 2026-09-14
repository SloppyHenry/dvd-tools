#!/usr/bin/env bash
# ---------- Darstellungsschicht ----------
# Saemtliche Terminalausgabe der Tools laeuft ueber dieses Modul, damit das
# Erscheinungsbild an einer Stelle definiert ist und ueberall gleich aussieht.
# Zwei Faehigkeiten werden zur Laufzeit erkannt und beeinflussen die Ausgabe:
# Farbe (nur bei echtem Terminal, respektiert NO_COLOR) und UTF-8 (sonst
# ASCII-Ersatzzeichen, damit nichts als Kaestchenmuell erscheint).

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_RESET=$(tput sgr0); C_BOLD=$(tput bold); C_DIM=$(tput dim)
  C_GREEN=$(tput setaf 2); C_YELLOW=$(tput setaf 3)
  C_RED=$(tput setaf 1); C_CYAN=$(tput setaf 6); C_BLUE=$(tput setaf 4)
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_BLUE=""
fi

case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*|*UTF8*|*utf-8*|*utf8*) DVD_UI_UNICODE=1 ;;
  *)                             DVD_UI_UNICODE=0 ;;
esac

if [ "$DVD_UI_UNICODE" -eq 1 ]; then
  G_STEP="▶"; G_OK="✔"; G_WARN="⚠"; G_ERR="✘"; G_ASK="❯"; G_DOT="·"
  G_LINE="─"; G_TL="╭"; G_TR="╮"; G_BL="╰"; G_BR="╯"; G_V="│"
  G_FULL="█"; G_EMPTY="░"; G_ARROW="→"
  SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
else
  G_STEP=">"; G_OK="+"; G_WARN="!"; G_ERR="x"; G_ASK=">"; G_DOT="-"
  G_LINE="-"; G_TL="+"; G_TR="+"; G_BL="+"; G_BR="+"; G_V="|"
  G_FULL="#"; G_EMPTY="."; G_ARROW="->"
  SPINNER_FRAMES=('|' '/' '-' '\')
fi

# term_cols -> aktuelle Terminalbreite (Fallback 80, falls nicht ermittelbar).
term_cols() { tput cols 2>/dev/null || echo 80; }

# Nutzbare Innenbreite fuer Rahmen/Trennlinien: die Terminalbreite, aber
# hoechstens 76 Zeichen, damit die Ausgabe auf breiten Terminals nicht
# quer ueber den ganzen Bildschirm laeuft und schlecht lesbar wird.
ui_width() {
  local c; c=$(term_cols)
  [ "$c" -gt 78 ] && c=78
  [ "$c" -lt 20 ] && c=20
  echo "$((c - 2))"
}

# repeat_char ZEICHEN ANZAHL
repeat_char() {
  local ch="$1" n="$2" out=""
  [ "$n" -lt 1 ] && { printf ''; return; }
  while [ "$n" -gt 0 ]; do out="$out$ch"; n=$((n - 1)); done
  printf '%s' "$out"
}

hr() { printf '  %s%s%s\n' "$C_DIM" "$(repeat_char "$G_LINE" "$(ui_width)")" "$C_RESET"; }

# ---------- Kopfzeile ----------
# Gerahmter Titel mit optionaler Unterzeile. Bewusst selbst gezeichnet statt
# per figlet: figlet ist nicht ueberall installiert, und der Fallback sah
# dann ganz anders aus als der Normalfall.
header() {
  local title="$1" subtitle="${2:-}" w; w=$(ui_width)
  local inner=$((w - 2))
  echo
  printf '  %s%s%s%s%s\n' "$C_CYAN" "$G_TL" "$(repeat_char "$G_LINE" "$inner")" "$G_TR" "$C_RESET"
  printf '  %s%s%s %s%-*s%s %s%s%s\n' \
    "$C_CYAN" "$G_V" "$C_RESET" \
    "$C_BOLD" "$((inner - 2))" "$(truncate_text "$title" "$((inner - 2))")" "$C_RESET" \
    "$C_CYAN" "$G_V" "$C_RESET"
  if [ -n "$subtitle" ]; then
    printf '  %s%s%s %s%-*s%s %s%s%s\n' \
      "$C_CYAN" "$G_V" "$C_RESET" \
      "$C_DIM" "$((inner - 2))" "$(truncate_text "$subtitle" "$((inner - 2))")" "$C_RESET" \
      "$C_CYAN" "$G_V" "$C_RESET"
  fi
  printf '  %s%s%s%s%s\n' "$C_CYAN" "$G_BL" "$(repeat_char "$G_LINE" "$inner")" "$G_BR" "$C_RESET"
}

# ---------- Meldungen ----------
# step() nummeriert automatisch durch, sobald STEP_TOTAL gesetzt ist - das
# gibt dem Nutzer waehrend eines mehrminuetigen Laufs Orientierung, wie weit
# der Ablauf insgesamt ist. Fuer Zwischenschritte innerhalb einer Phase
# (z.B. die zwei ddrescue-Durchlaeufe) gibt es substep().
STEP_TOTAL="${STEP_TOTAL:-0}"
STEP_NUM=0
step() {
  echo
  if [ "$STEP_TOTAL" -gt 0 ]; then
    STEP_NUM=$((STEP_NUM + 1))
    printf '%s%s %s/%s%s  %s%s%s\n' \
      "$C_CYAN" "$G_STEP" "$STEP_NUM" "$STEP_TOTAL" "$C_RESET" \
      "$C_BOLD" "$*" "$C_RESET"
  else
    printf '%s%s%s  %s%s%s\n' "$C_CYAN" "$G_STEP" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"
  fi
}
substep() { printf '   %s%s%s %s\n' "$C_DIM" "$G_DOT" "$C_RESET" "$*"; }
info()    { printf '   %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
ok()      { printf ' %s%s%s %s\n' "$C_GREEN" "$G_OK" "$C_RESET" "$*"; }
warn()    { printf ' %s%s %s%s\n' "$C_YELLOW" "$G_WARN" "$*" "$C_RESET" >&2; }
err()     { printf ' %s%s %s%s\n' "$C_RED" "$G_ERR" "$*" "$C_RESET" >&2; }

# kv SCHLUESSEL WERT -> ausgerichtete Wertezeile. Die Schluesselspalte ist
# fest breit, damit untereinander stehende Werte eine saubere Kante bilden.
kv() {
  local key="$1" val="$2" w; w=$(ui_width)
  printf '   %s%-9s%s %s\n' "$C_DIM" "$key" "$C_RESET" "$(truncate_text "$val" "$((w - 11))")"
}

# kv_full SCHLUESSEL WERT -> wie kv(), kappt den Wert aber nie. Fuer Pfade im
# Abschlussbericht: die will der Nutzer kopieren koennen, ein "…" mittendrin
# macht die Ausgabe dort unbrauchbar. Der Wert steht deshalb auf einer
# eigenen, eingerueckten Zeile und darf umbrechen.
kv_full() {
  printf '   %s%s%s\n     %s\n' "$C_DIM" "$1" "$C_RESET" "$2"
}

# menu_item NUMMER TEXT [ZUSATZ] -> Eintrag einer Auswahlliste.
menu_item() {
  local n="$1" text="$2" extra="${3:-}" w; w=$(ui_width)
  local budget=$((w - 8 - ${#extra}))
  [ "$budget" -lt 10 ] && budget=10
  printf '   %s[%2s]%s %s' "$C_BOLD" "$n" "$C_RESET" "$(truncate_text "$text" "$budget")"
  [ -n "$extra" ] && printf '  %s%s%s' "$C_DIM" "$extra" "$C_RESET"
  echo
}

# ask VARIABLE FRAGE [VORGABE] -> liest eine Eingabe in VARIABLE. Bleibt die
# Eingabe leer, greift die Vorgabe (die auch sichtbar angezeigt wird).
ask() {
  local __var="$1" prompt="$2" default="${3:-}" reply hint=""
  [ -n "$default" ] && hint=" ${C_DIM}[$default]${C_RESET}"
  printf ' %s%s%s %s%s ' "$C_BLUE" "$G_ASK" "$C_RESET" "$prompt" "$hint" >&2
  read -r reply
  printf -v "$__var" '%s' "${reply:-$default}"
}

# confirm FRAGE -> Rueckgabe 0 bei Ja. Standard ist immer Nein, damit ein
# versehentliches Enter nie etwas ausloest oder loescht.
confirm() {
  local reply
  printf ' %s%s%s %s %s[j/N]%s ' "$C_BLUE" "$G_ASK" "$C_RESET" "$1" "$C_DIM" "$C_RESET" >&2
  read -r reply
  [[ "$reply" =~ ^[jJyY]$ ]]
}

# truncate_text TEXT MAXLEN -> kappt TEXT hart auf MAXLEN Zeichen (mit "…"),
# damit dynamische Live-Zeilen (Fortschrittsbalken/Spinner) nie die
# Terminalbreite ueberschreiten. Ohne Kappung bricht eine zu lange Zeile um
# und die "\r"-basierte Neuzeichnung zerstoert dann die Anzeige (Reste der
# vorherigen, umgebrochenen Zeile bleiben stehen -> "flackert und verschwindet").
truncate_text() {
  local text="$1" max="$2"
  [ "$max" -lt 1 ] && max=1
  [ "$DVD_UI_UNICODE" -eq 0 ] && [ "$max" -lt 4 ] && max=4
  if [ "${#text}" -gt "$max" ]; then
    if [ "$DVD_UI_UNICODE" -eq 1 ]; then
      echo "${text:0:$((max - 1))}…"
    else
      echo "${text:0:$((max - 3))}..."
    fi
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
  # Fixer Anteil: "  " (2) + Balken + "  " (2) + Prozent (6) + "  " (2)
  # = 12 + width. Ein Zeichen Reserve, damit die Zeile nie exakt bis zur
  # letzten Spalte reicht (manche Terminals brechen dann schon um).
  local max_label=$(( term_width - width - 13 ))
  [ "$max_label" -lt 3 ] && max_label=3
  label="$(truncate_text "$label" "$max_label")"
  printf '\r\033[K  %s%s%s%s%s  %s%5.1f%%%s  %s' \
    "$C_GREEN" "$(repeat_char "$G_FULL" "$filled")" \
    "$C_DIM" "$(repeat_char "$G_EMPTY" "$empty")" "$C_RESET" \
    "$C_BOLD" "$pct" "$C_RESET" "$label"
}
progress_done() { echo; }

# Einzeiliger Spinner fuer Phasen ohne bekannten Prozentwert (z.B. Disc-Scan,
# oder wenn die zugrundeliegende Kennzahl - hier MakeMKV-PRGV - gar nicht
# geliefert wird). Nutzung: in einer Schleife wiederholt spinner_line "Text"
SPINNER_I=0
spinner_line() {
  local text="${1:-Arbeite...}"
  local frame="${SPINNER_FRAMES[$((SPINNER_I % ${#SPINNER_FRAMES[@]}))]}"
  SPINNER_I=$((SPINNER_I + 1))
  local max_text=$(( $(term_cols) - 6 ))
  [ "$max_text" -lt 3 ] && max_text=3
  text="$(truncate_text "$text" "$max_text")"
  printf '\r\033[K  %s%s%s %s' "$C_CYAN" "$frame" "$C_RESET" "$text"
}

need() {
  command -v "$1" >/dev/null 2>&1 || { err "'$1' ist nicht installiert."; exit 1; }
}

# human_bytes N -> "1.8 GB" / "742 MB", feste, kurze Darstellung.
human_bytes() {
  awk -v b="${1:-0}" 'BEGIN{
    if (b >= 1073741824) printf "%.1f GB", b/1073741824
    else                 printf "%d MB",   b/1048576
  }'
}

# size_summary ALT_BYTES NEU_BYTES -> "4.3 GB → 1.6 GB  (-63 %)".
# Der Ersparnis-Prozentsatz ist die eigentlich interessante Zahl am Ende
# eines Laufs, wurde bisher aber nicht ausgerechnet.
size_summary() {
  local old="${1:-0}" new="${2:-0}" pct=""
  if [ "$old" -gt 0 ] && [ "$new" -gt 0 ]; then
    pct="$(awk -v o="$old" -v n="$new" 'BEGIN{printf "%+.0f", (n-o)*100/o}')"
    printf '%s %s %s  %s(%s %%)%s' \
      "$(human_bytes "$old")" "$G_ARROW" "$(human_bytes "$new")" \
      "$C_BOLD" "$pct" "$C_RESET"
  else
    printf '%s %s %s' "$(human_bytes "$old")" "$G_ARROW" "$(human_bytes "$new")"
  fi
}
