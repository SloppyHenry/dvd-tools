#!/usr/bin/env bash
# ---------- Filmdatenbank-Anbieter ----------
# Liefert zu einem Suchbegriff Kandidatenzeilen im Format
#   tmdb_id \t titel \t jahr \t laufzeit_minuten
# (Laufzeit darf leer sein). Zwei Anbieter:
#
#   wikidata  ohne Anmeldung/Key nutzbar, liefert die TMDB-ID gleich mit
#             (Wikidata-Eigenschaft P4947) - deshalb passt das Ergebnis
#             weiterhin ins Namensschema "Titel (Jahr) [tmdbid-ID]".
#   tmdb      braucht einen kostenlosen API-Key, dafuer die vollstaendigste
#             und aktuellste Datenbasis.
#
# Steuerbar ueber DVD_TOOLS_METADATA_PROVIDER in ~/.config/dvd-tools/config:
#   auto (Vorgabe) | tmdb | wikidata | off

DVD_TOOLS_METADATA_PROVIDER="${DVD_TOOLS_METADATA_PROVIDER:-auto}"
DVD_TOOLS_USER_AGENT="dvd-tools (+https://github.com/SloppyHenry/dvd-tools)"

# tmdb_search QUERY -> Kandidatenzeilen, Rueckgabe 1 ohne API-Key.
# TMDBs Suchtreffer enthalten keine Laufzeit (die stuende erst im
# Detail-Endpunkt), das vierte Feld bleibt hier daher leer.
tmdb_search() {
  local query="$1"
  [ -z "${TMDB_API_KEY:-}" ] && return 1
  curl -fsS --max-time 20 --get "https://api.themoviedb.org/3/search/movie" \
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
    print(f"{mid}\t{title}\t{year}\t")
' 2>/dev/null
}

# wikidata_search QUERY -> Kandidatenzeilen, ohne jeden API-Key.
#
# Zwei Aufrufe der MediaWiki-API statt einer SPARQL-Abfrage: der
# SPARQL-Endpunkt wuerde die Relevanzsortierung der Suche verlieren (bei
# "Matrix" stuende dann irgendein Dokumentarfilm oben) und ist ausserdem
# haeufiger ueberlastet.
#   1. CirrusSearch (list=search) - fehlertolerante Volltextsuche. Wichtig,
#      weil DVD-Labels keine Umlaute/Satzzeichen enthalten duerfen
#      ("GEFAEHRTEN" findet so trotzdem "Die Gefährten"). Der Zusatz
#      haswbstatement:P31=Q11424 beschraenkt auf Filme.
#   2. wbgetentities - holt zu den gefundenen IDs Titel, Erscheinungsjahr
#      (P577), Laufzeit (P2047) und TMDB-ID (P4947).
# Der Suchbegriff wird ueber argv uebergeben, nie in den Quelltext
# interpoliert. Netzwerk-/Parse-Fehler fuehren zu leerer Ausgabe statt zu
# einem Traceback vor den Augen des Nutzers.
wikidata_search() {
  python3 - "$1" "$DVD_TOOLS_USER_AGENT" <<'PY' 2>/dev/null
import json, sys, urllib.parse, urllib.request

query, user_agent = sys.argv[1], sys.argv[2]
API = "https://www.wikidata.org/w/api.php"


def api(**params):
    params["format"] = "json"
    req = urllib.request.Request(
        API + "?" + urllib.parse.urlencode(params),
        headers={"User-Agent": user_agent},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)


def claims(entity, prop):
    for c in entity.get("claims", {}).get(prop, []):
        if "datavalue" in c.get("mainsnak", {}):
            yield c["mainsnak"]["datavalue"]["value"]


try:
    found = api(action="query", list="search", srnamespace=0, srlimit=8,
                srsearch=f"{query} haswbstatement:P31=Q11424")
    qids = [hit["title"] for hit in found.get("query", {}).get("search", [])]
    if not qids:
        sys.exit(0)
    entities = api(action="wbgetentities", ids="|".join(qids),
                   props="labels|claims", languages="de|en").get("entities", {})
except Exception:
    sys.exit(1)

for qid in qids:                       # Reihenfolge beibehalten = Relevanz
    entity = entities.get(qid, {})
    labels = entity.get("labels", {})
    title = (labels.get("de") or labels.get("en") or {}).get("value", "")
    if not title:
        continue
    tmdb = next(iter(claims(entity, "P4947")), "")
    years = [v["time"][1:5] for v in claims(entity, "P577")]
    # Fruehestes Datum: Wikidata fuehrt oft mehrere Veroeffentlichungen
    # (Festival, Kinostart je Land) - gemeint ist das Erscheinungsjahr.
    year = min(years) if years else ""
    try:
        duration = str(int(float(next(iter(claims(entity, "P2047")))["amount"])))
    except Exception:
        duration = ""
    print(f"{tmdb}\t{title.replace(chr(9), ' ')}\t{year}\t{duration}")
PY
}

# label_is_generic LABEL -> 0, wenn das Disc-Label erkennbar nichtssagend ist
# (Standardwerte von Authoring-Programmen, Platzhalter, reine Nummern). Dann
# lohnt keine Online-Suche: sie kostet nur Zeit und liefert bestenfalls
# zufaellige Treffer.
label_is_generic() {
  local l; l="$(tr '[:lower:]' '[:upper:]' <<<"$1" | tr -d ' _.-')"
  [ "${#l}" -lt 3 ] && return 0
  case "$l" in
    DVD|DVDVIDEO|DVDVOLUME|VIDEODVD|DVDROM|UNTITLED|NONAME|NOLABEL|MOVIE|\
    LOGICALVOLUMEID|VOLUME|MYDISC|NEWVOLUME|UNBENANNT|DISC*|TITLE*|B[0-9]*T[0-9]*)
      return 0 ;;
  esac
  [[ "$l" =~ ^[0-9]+$ ]] && return 0
  return 1
}

# movie_search QUERY -> fuellt die globalen MOVIE_CANDIDATES (Zeilen wie oben)
# und MOVIE_SEARCH_PROVIDER (Anzeigename des tatsaechlich benutzten Anbieters).
# Rueckgabe 1, wenn nichts gefunden wurde.
#
# Bewusst ueber globale Arrays statt ueber die Standardausgabe: ein
# "mapfile < <(movie_search ...)" liefe in einer Subshell, der gewaehlte
# Anbieter waere beim Aufrufer dann nicht mehr sichtbar.
#
# Bei "auto" wird TMDB bevorzugt, sofern ein Key vorliegt, und bei leerem
# Ergebnis zusaetzlich Wikidata versucht - die beiden Datenbasen decken sich
# nicht vollstaendig.
# shellcheck disable=SC2034  # MOVIE_CANDIDATES/MOVIE_SEARCH_PROVIDER sind die Ausgabe an den Aufrufer
movie_search() {
  local query="$1" rows=""
  MOVIE_CANDIDATES=()
  MOVIE_SEARCH_PROVIDER=""

  case "$DVD_TOOLS_METADATA_PROVIDER" in
    off)      return 1 ;;
    tmdb)     rows="$(tmdb_search "$query")";     MOVIE_SEARCH_PROVIDER="TMDB" ;;
    wikidata) rows="$(wikidata_search "$query")"; MOVIE_SEARCH_PROVIDER="Wikidata" ;;
    *)
      if [ -n "${TMDB_API_KEY:-}" ]; then
        rows="$(tmdb_search "$query")"
        [ -n "$rows" ] && MOVIE_SEARCH_PROVIDER="TMDB"
      fi
      if [ -z "$rows" ]; then
        rows="$(wikidata_search "$query")"
        [ -n "$rows" ] && MOVIE_SEARCH_PROVIDER="Wikidata"
      fi
      ;;
  esac

  [ -z "$rows" ] && return 1
  mapfile -t MOVIE_CANDIDATES <<<"$rows"
  [ "${#MOVIE_CANDIDATES[@]}" -gt 0 ]
}
