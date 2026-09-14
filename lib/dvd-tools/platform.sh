#!/usr/bin/env bash
# ---------- Plattform-Abstraktion (Linux/Debian und macOS) ----------
# Alles hier kapselt Unterschiede zwischen GNU-Userland (Linux) und
# BSD-Userland (macOS): date/readlink/stat/du-Flags, eject, Encoder-Wahl.
DVD_TOOLS_OS="$(uname -s)"   # "Linux" oder "Darwin"

is_macos() { [ "$DVD_TOOLS_OS" = "Darwin" ]; }

# now_seconds -> Sekunden seit Epoch mit Nachkommastellen.
# "date +%s.%N" gibt es nur unter GNU/Linux (BSD-date auf macOS versteht
# %N nicht) - python3 ist ohnehin Pflichtabhaengigkeit, also darueber.
now_seconds() { python3 -c 'import time; print(time.time())'; }

# resolve_path PATH -> absoluter, aufgeloester Pfad (Ersatz fuer
# "readlink -f", das es unter macOS/BSD nicht gibt).
resolve_path() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

# file_size_bytes PATH -> Groesse in Bytes ("stat -c%s" ist GNU-spezifisch,
# BSD/macOS-stat braucht "-f%z").
file_size_bytes() {
  if is_macos; then
    stat -f%z "$1" 2>/dev/null || echo 0
  else
    stat -c%s "$1" 2>/dev/null || echo 0
  fi
}

# dir_size_bytes PATH -> Gesamtgroesse eines Verzeichnisses in Bytes
# ("du -sb" ist GNU-spezifisch, BSD-du kennt kein -b).
dir_size_bytes() {
  if is_macos; then
    du -sk "$1" 2>/dev/null | awk '{print $1*1024}'
  else
    du -sb "$1" 2>/dev/null | cut -f1
  fi
}

# cpu_count -> Anzahl CPU-Kerne ("nproc" gibt es unter macOS nicht).
cpu_count() {
  if is_macos; then
    sysctl -n hw.ncpu 2>/dev/null || echo 4
  else
    nproc 2>/dev/null || echo 4
  fi
}

# eject_disc DEVICE -> wirft die Disc aus (macOS: drutil/diskutil,
# Linux: eject).
eject_disc() {
  local drive="$1"
  if is_macos; then
    drutil eject "$drive" >/dev/null 2>&1 || diskutil eject "$drive" >/dev/null 2>&1
  else
    eject "$drive" >/dev/null 2>&1
  fi
}

# Liste der von der installierten HandBrakeCLI tatsaechlich unterstuetzten
# Video-Encoder (einmal pro Lauf ermittelt und gecacht). Wichtig: das ist
# die Quelle der Wahrheit dafuer, was waehlbar ist - nicht Plattform-
# Annahmen, denn nicht jeder HandBrake-Build hat QSV/VAAPI mit einkompiliert.
_HB_ENCODERS_CACHE=""
handbrake_encoders() {
  if [ -z "$_HB_ENCODERS_CACHE" ]; then
    _HB_ENCODERS_CACHE="$(HandBrakeCLI -h 2>/dev/null | awk '
      /--encoder <string>/ { f=1; next }
      f && /^\s+[a-zA-Z0-9_]+\s*$/ { gsub(/^[ \t]+|[ \t]+$/, ""); print; next }
      f && /^\s*$/ { exit }
      f && /^\s+-/ { exit }
    ')"
  fi
  printf '%s\n' "$_HB_ENCODERS_CACHE"
}

hb_has_encoder() { handbrake_encoders | grep -qx "$1"; }

# pick_hevc_encoder -> prueft live, welche GPU vorhanden ist und welche
# HEVC-Hardware-Encoder die installierte HandBrakeCLI dafuer tatsaechlich
# mitbringt (NVENC/NVIDIA, QSV/Intel, VCE/AMD, VideoToolbox/macOS) -
# faellt auf Software-x265 zurueck, wenn nichts Passendes gefunden wird.
pick_hevc_encoder() {
  if is_macos; then
    hb_has_encoder vt_h265 && { echo "vt_h265"; return; }
    echo "x265"
    return
  fi

  local gpu_info=""
  command -v lspci >/dev/null 2>&1 && gpu_info="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display')"

  if echo "$gpu_info" | grep -qi nvidia \
     && command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 \
     && hb_has_encoder nvenc_h265; then
    echo "nvenc_h265"; return
  fi
  if echo "$gpu_info" | grep -qi intel && hb_has_encoder qsv_h265; then
    echo "qsv_h265"; return
  fi
  if echo "$gpu_info" | grep -Eqi 'amd|ati|advanced micro devices' && hb_has_encoder vce_h265; then
    echo "vce_h265"; return
  fi
  # GPU-Erkennung war nicht eindeutig/erfolglos - trotzdem lieber irgendeinen
  # von HandBrake tatsaechlich angebotenen Hardware-Encoder nehmen, bevor
  # auf Software ausgewichen wird.
  local enc
  for enc in nvenc_h265 qsv_h265 vce_h265; do
    hb_has_encoder "$enc" && { echo "$enc"; return; }
  done
  echo "x265"
}

