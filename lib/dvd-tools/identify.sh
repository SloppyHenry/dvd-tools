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

  if label_is_generic "$label"; then
    info "Disc-Label \"$label\" ist nichtssagend - Online-Suche uebersprungen."
    ask TITLE "Filmtitel"
    ask YEAR "Erscheinungsjahr (optional)"
    ask TMDBID "TMDB-ID (optional)"
    return
  fi

  substep "Suche \"$guess\" ..."
  movie_search "$guess"
  local -a CANDIDATES=("${MOVIE_CANDIDATES[@]}")
  local provider="${MOVIE_SEARCH_PROVIDER:-}"

  if [ "${#CANDIDATES[@]}" -gt 0 ]; then
    local top_id top_title top_year sim
    top_id="$(cut -f1 <<<"${CANDIDATES[0]}")"
    top_title="$(cut -f2 <<<"${CANDIDATES[0]}")"
    top_year="$(cut -f3 <<<"${CANDIDATES[0]}")"
    sim="$(similarity "$guess" "$top_title")"

    if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= 0.72 else 1)" "$sim"; then
      ok "Erkannt: $top_title ($top_year) [tmdbid-$top_id]${provider:+  (Quelle: $provider)}"
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
    warn "Unsicher - mehrere moegliche Treffer fuer \"$guess\"${provider:+ (Quelle: $provider)}:"
    for i in "${!CANDIDATES[@]}"; do
      # Laufzeit mit anzeigen, sofern bekannt: sie unterscheidet Hauptfilm,
      # Kurzfilm und Dokumentation oft zuverlaessiger als der Titel allein.
      local c_year c_dur
      c_year="$(cut -f3 <<<"${CANDIDATES[$i]}")"
      c_dur="$(cut -f4 <<<"${CANDIDATES[$i]}")"
      menu_item "$((i+1))" "$(cut -f2 <<<"${CANDIDATES[$i]}")" \
        "$(printf '%-6s%s' "$c_year" "${c_dur:+${c_dur} min}")"
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
    warn "Keine Treffer fuer \"$guess\"."
  fi

  ask TITLE "Filmtitel" "$guess"
  ask YEAR "Erscheinungsjahr (optional)"
  ask TMDBID "TMDB-ID (optional)"
}

