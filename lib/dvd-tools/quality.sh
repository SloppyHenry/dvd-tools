#!/usr/bin/env bash
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

