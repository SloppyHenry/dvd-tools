#!/usr/bin/env bash
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
