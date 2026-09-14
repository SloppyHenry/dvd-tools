#!/usr/bin/env bash
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
# shellcheck disable=SC2034  # YEAR/TMDBID sind absichtlich globale Ausgabe an den Aufrufer
identify_from_label() {
  local label="$1"
  local guess; guess="$(clean_disc_label "$label")"
  TITLE=""; YEAR=""; TMDBID=""

  if [ -z "${TMDB_API_KEY:-}" ]; then
    warn "Keine TMDB_API_KEY gesetzt (siehe README) - automatische Erkennung uebersprungen."
    ask TITLE "Filmtitel" "$guess"
    ask YEAR "Erscheinungsjahr (optional)"
    ask TMDBID "TMDB-ID (optional)"
    return
  fi

  substep "Suche \"$guess\" bei TMDB ..."
  mapfile -t CANDIDATES < <(tmdb_search "$guess")

  if [ "${#CANDIDATES[@]}" -gt 0 ]; then
    local top_id top_title top_year sim
    top_id="$(cut -f1 <<<"${CANDIDATES[0]}")"
    top_title="$(cut -f2 <<<"${CANDIDATES[0]}")"
    top_year="$(cut -f3 <<<"${CANDIDATES[0]}")"
    sim="$(similarity "$guess" "$top_title")"

    if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= 0.72 else 1)" "$sim"; then
      ok "Erkannt: $top_title ($top_year) [tmdbid-$top_id]"
      # Hier ist Ja die Vorgabe (anders als bei confirm()): der Treffer gilt
      # als sicher genug, Enter soll ihn uebernehmen.
      printf ' %s%s%s Uebernehmen? %s[J/n]%s ' \
        "$C_BLUE" "$G_ASK" "$C_RESET" "$C_DIM" "$C_RESET" >&2
      read -r CONFIRM_GUESS
      if ! [[ "$CONFIRM_GUESS" =~ ^[nN]$ ]]; then
        TITLE="$top_title"; YEAR="$top_year"; TMDBID="$top_id"
        return
      fi
    fi
  fi

  if [ "${#CANDIDATES[@]}" -gt 0 ]; then
    warn "Unsicher - mehrere moegliche Treffer fuer \"$guess\":"
    for i in "${!CANDIDATES[@]}"; do
      menu_item "$((i+1))" "$(cut -f2 <<<"${CANDIDATES[$i]}")" \
        "$(cut -f3 <<<"${CANDIDATES[$i]}")"
    done
    menu_item "0" "Manuell eingeben"
    echo
    ask PICK "Auswahl" "1"
    if [[ "$PICK" =~ ^[0-9]+$ ]] && [ "$PICK" -ge 1 ] && [ "$PICK" -le "${#CANDIDATES[@]}" ]; then
      local row="${CANDIDATES[$((PICK-1))]}"
      TMDBID="$(cut -f1 <<<"$row")"; TITLE="$(cut -f2 <<<"$row")"; YEAR="$(cut -f3 <<<"$row")"
      return
    fi
  else
    warn "Keine TMDB-Treffer fuer \"$guess\"."
  fi

  ask TITLE "Filmtitel" "$guess"
  ask YEAR "Erscheinungsjahr (optional)"
  ask TMDBID "TMDB-ID (optional)"
}

