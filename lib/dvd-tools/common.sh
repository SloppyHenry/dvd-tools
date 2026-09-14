#!/usr/bin/env bash
# Laedt die gemeinsamen Funktionen fuer dvd-shrink / dvd-auto aus den
# Modulen in diesem Verzeichnis. Wird per `source` eingebunden, kein
# eigenstaendiges Skript. Aufgeteilt, weil eine einzelne Datei mit allen
# Funktionen irgendwann ueber 600 Zeilen wuchs (siehe CLAUDE.md: max. ~300,
# hart 500 Zeilen pro Datei).

# printf mit "." als Dezimaltrennzeichen erzwingen (unabhaengig von der Systemlocale,
# sonst schlaegt z.B. printf %f mit "25.5" unter de_DE fehl).
export LC_NUMERIC=C

# Optionale Konfiguration (z.B. TMDB_API_KEY=...) aus ~/.config/dvd-tools/config laden.
DVD_TOOLS_CONFIG="${DVD_TOOLS_CONFIG:-$HOME/.config/dvd-tools/config}"
# shellcheck disable=SC1090  # echter Laufzeitpfad (Nutzer-Config), fuer shellcheck nicht auflösbar
[ -f "$DVD_TOOLS_CONFIG" ] && source "$DVD_TOOLS_CONFIG"

_COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _f in platform ui naming quality metadata identify rip encode; do
  # shellcheck source=/dev/null
  source "$_COMMON_SH_DIR/${_f}.sh"
done
unset _f _COMMON_SH_DIR
