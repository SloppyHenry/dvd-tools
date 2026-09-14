#!/usr/bin/env bash
# ---------- Namensschema ----------
# build_basename TITLE YEAR TMDBID -> "Titel (Jahr) [tmdbid-ID]"
build_basename() {
  local title="$1" year="$2" tmdbid="$3" base="$1"
  [ -n "$year" ] && base="${base} (${year})"
  [ -n "$tmdbid" ] && base="${base} [tmdbid-${tmdbid}]"
  # Dateisystem-verbotene Zeichen durch Leerzeichen ersetzen statt loeschen
  # (sonst wuerde z.B. "AC/DC" zu "ACDC" verschmelzen), danach doppelte
  # Leerzeichen zusammenziehen und am Rand trimmen.
  echo "$base" | tr '/\\:*?"<>|' ' ' | tr -s ' ' | sed -E 's/^ +| +$//g'
}

# write_tags_xml TITLE YEAR OUTFILE
# xml_escape TEXT -> XML-sichere Version (Titel wie "Fast & Furious" wuerden
# sonst die Tags-XML unbrauchbar machen).
xml_escape() {
  local s="$1"
  # "\&" im Replacement ist Pflicht: bash behandelt ein unmaskiertes "&" in
  # ${var//pattern/replacement} als Backreferenz auf den getroffenen Text
  # (wie bei sed) - ohne die Maskierung wuerde sich das Escaping selbst
  # kaputtmachen (z.B. "<" -> "<lt;" statt "&lt;").
  s="${s//&/\&amp;}"
  s="${s//</\&lt;}"
  s="${s//>/\&gt;}"
  s="${s//\"/\&quot;}"
  s="${s//\'/\&apos;}"
  printf '%s' "$s"
}

write_tags_xml() {
  local title="$1" year="$2" outfile="$3"
  local title_esc; title_esc="$(xml_escape "$title")"
  local year_esc; year_esc="$(xml_escape "$year")"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE Tags SYSTEM "matroskatags.dtd">'
    echo '<Tags>'
    echo '  <Tag>'
    echo '    <Targets><TargetTypeValue>50</TargetTypeValue></Targets>'
    echo "    <Simple><Name>TITLE</Name><String>${title_esc}</String></Simple>"
    if [ -n "$year" ]; then
      echo "    <Simple><Name>DATE_RELEASED</Name><String>${year_esc}</String></Simple>"
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

