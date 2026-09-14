#!/usr/bin/env bash
# Installiert dvd-tools + alle Laufzeitabhaengigkeiten.
#
# - HandBrakeCLI, mkvtoolnix, ffmpeg, python3: ueber apt (Debian/Ubuntu)
# - MakeMKV (makemkvcon): wird, falls nicht vorhanden, aus dem offiziellen
#   Quellcode gebaut (makemkv-oss kompiliert, makemkv-bin als offizielles
#   Binaerpaket installiert - siehe README fuer den Hintergrund)
# - dvd-shrink / dvd-auto: nach ~/.local/bin bzw. ~/.local/lib/dvd-tools
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LIB_DIR="$HOME/.local/lib/dvd-tools"
MAKEMKV_VERSION="${MAKEMKV_VERSION:-1.18.4}"

if [ -t 1 ]; then
  C_GREEN=$(tput setaf 2); C_YELLOW=$(tput setaf 3); C_RED=$(tput setaf 1)
  C_CYAN=$(tput setaf 6); C_BOLD=$(tput bold); C_RESET=$(tput sgr0)
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_BOLD=""; C_RESET=""
fi
step() { echo "${C_CYAN}${C_BOLD}▶ $*${C_RESET}"; }
ok()   { echo "${C_GREEN}✔ $*${C_RESET}"; }
warn() { echo "${C_YELLOW}⚠ $*${C_RESET}"; }
err()  { echo "${C_RED}✘ $*${C_RESET}" >&2; }

if ! command -v apt-get >/dev/null 2>&1; then
  err "Dieses Installationsskript unterstuetzt nur apt-basierte Systeme (Debian/Ubuntu)."
  err "Auf anderen Distributionen bitte die Pakete aus der README manuell installieren."
  exit 1
fi

step "Installiere Laufzeit- und Build-Abhaengigkeiten ueber apt..."
sudo apt-get update
sudo apt-get install -y \
  handbrake-cli mkvtoolnix ffmpeg python3 curl eject util-linux gddrescue \
  build-essential pkg-config libc6-dev libssl-dev libexpat1-dev \
  libavcodec-dev libavutil-dev zlib1g-dev
ok "apt-Pakete installiert."

if command -v makemkvcon >/dev/null 2>&1; then
  ok "makemkvcon bereits vorhanden ($(command -v makemkvcon)), Build wird uebersprungen."
else
  step "Baue MakeMKV $MAKEMKV_VERSION aus dem offiziellen Quellcode..."
  echo "  (makemkv-oss ist quelloffen, makemkv-bin ist die proprietaere"
  echo "   Entschluesselungsbibliothek als offizielles Binaerpaket - siehe README)"
  BUILD_DIR="$(mktemp -d)"
  trap 'rm -rf "$BUILD_DIR"' EXIT
  (
    cd "$BUILD_DIR"
    curl -fSLO "https://www.makemkv.com/download/makemkv-oss-${MAKEMKV_VERSION}.tar.gz"
    curl -fSLO "https://www.makemkv.com/download/makemkv-bin-${MAKEMKV_VERSION}.tar.gz"

    tar xzf "makemkv-oss-${MAKEMKV_VERSION}.tar.gz"
    (cd "makemkv-oss-${MAKEMKV_VERSION}" && ./configure --disable-gui && make -j"$(nproc)" && sudo make install)

    tar xzf "makemkv-bin-${MAKEMKV_VERSION}.tar.gz"
    echo
    echo "MakeMKV verlangt beim ersten Build die Zustimmung zur eigenen EULA:"
    (cd "makemkv-bin-${MAKEMKV_VERSION}" && make && sudo make install)
  )
  rm -rf "$BUILD_DIR"
  trap - EXIT
  ok "makemkvcon gebaut und installiert."
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  ok "NVIDIA-GPU erkannt, NVENC sollte verfuegbar sein."
else
  warn "Keine NVIDIA-GPU/Treiber gefunden. nvenc_h265 in HandBrake wird nicht funktionieren -"
  warn "encode_to_hevc in lib/dvd-tools/common.sh muesste auf 'x265' (Software) umgestellt werden."
fi

step "Installiere dvd-tools nach $BIN_DIR und $LIB_DIR..."
mkdir -p "$BIN_DIR" "$LIB_DIR"
cp -v "$SRC_DIR"/bin/* "$BIN_DIR/"
cp -v "$SRC_DIR"/lib/dvd-tools/* "$LIB_DIR/"
chmod +x "$BIN_DIR"/dvd-shrink "$BIN_DIR"/dvd-auto
ok "dvd-tools installiert."

echo
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  warn "$BIN_DIR ist nicht in deinem PATH. Fuege hinzu (z.B. in ~/.bashrc):"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
fi

echo
echo "Optional fuer automatische Titelerkennung (dvd-auto):"
echo "  mkdir -p ~/.config/dvd-tools"
echo "  cp $SRC_DIR/config.example ~/.config/dvd-tools/config"
echo "  # dann TMDB_API_KEY in der Datei eintragen"
echo
ok "Fertig."
