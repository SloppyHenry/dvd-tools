#!/usr/bin/env bash
# Installiert dvd-tools + alle Laufzeitabhaengigkeiten.
# Unterstuetzt Debian/Ubuntu (apt) und macOS (Homebrew).
#
# - HandBrakeCLI, mkvtoolnix, ffmpeg, python3, ddrescue: ueber apt bzw. brew
# - MakeMKV (makemkvcon):
#     Linux: wird, falls nicht vorhanden, aus dem offiziellen Quellcode
#            gebaut (makemkv-oss kompiliert, makemkv-bin als offizielles
#            Binaerpaket installiert - siehe README fuer den Hintergrund)
#     macOS: ueber "brew install --cask makemkv" (offizieller Weg dort),
#            makemkvcon wird danach nach BIN_DIR verlinkt
# - dvd-shrink / dvd-auto: nach ~/.local/bin bzw. ~/.local/lib/dvd-tools
set -euo pipefail

# "readlink -f" gibt es unter macOS/BSD nicht - erst pruefen, ob python3
# schon da ist (wird gleich sowieso benoetigt), sonst auf "cd+pwd" ohne
# Symlink-Aufloesung ausweichen.
if command -v python3 >/dev/null 2>&1; then
  SRC_DIR="$(cd "$(dirname "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$0")")" && pwd)"
else
  SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
BIN_DIR="$HOME/.local/bin"
LIB_DIR="$HOME/.local/lib/dvd-tools"
MAKEMKV_VERSION="${MAKEMKV_VERSION:-1.18.4}"
OS="$(uname -s)"

if [ -t 1 ]; then
  C_GREEN=$(tput setaf 2); C_YELLOW=$(tput setaf 3); C_RED=$(tput setaf 1)
  C_CYAN=$(tput setaf 6); C_BOLD=$(tput bold); C_RESET=$(tput sgr0)
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_BOLD=""; C_RESET=""
fi
step() { echo "${C_CYAN}${C_BOLD}▶ $*${C_RESET}"; }
info() { echo "  $*"; }
ok()   { echo "${C_GREEN}✔ $*${C_RESET}"; }
warn() { echo "${C_YELLOW}⚠ $*${C_RESET}"; }
err()  { echo "${C_RED}✘ $*${C_RESET}" >&2; }

cpu_count() {
  if [ "$OS" = "Darwin" ]; then sysctl -n hw.ncpu 2>/dev/null || echo 4
  else nproc 2>/dev/null || echo 4; fi
}

case "$OS" in
  Linux)
    if ! command -v apt-get >/dev/null 2>&1; then
      err "Dieses Installationsskript unterstuetzt unter Linux nur apt-basierte"
      err "Systeme (Debian/Ubuntu). Auf anderen Distributionen bitte die Pakete"
      err "aus der README manuell installieren."
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
        (cd "makemkv-oss-${MAKEMKV_VERSION}" && ./configure --disable-gui && make -j"$(cpu_count)" && sudo make install)

        tar xzf "makemkv-bin-${MAKEMKV_VERSION}.tar.gz"
        echo
        echo "MakeMKV verlangt beim ersten Build die Zustimmung zur eigenen EULA:"
        (cd "makemkv-bin-${MAKEMKV_VERSION}" && make && sudo make install)
      )
      rm -rf "$BUILD_DIR"
      trap - EXIT
      ok "makemkvcon gebaut und installiert."
    fi
    ;;

  Darwin)
    if ! command -v brew >/dev/null 2>&1; then
      err "Homebrew wurde nicht gefunden. Bitte zuerst installieren: https://brew.sh"
      exit 1
    fi

    step "Installiere Laufzeitabhaengigkeiten ueber Homebrew..."
    brew install handbrake mkvtoolnix ffmpeg python3 ddrescue curl || true
    ok "Homebrew-Pakete installiert."

    if command -v makemkvcon >/dev/null 2>&1; then
      ok "makemkvcon bereits vorhanden ($(command -v makemkvcon))."
    else
      step "Installiere MakeMKV ueber Homebrew Cask..."
      brew install --cask makemkv
      MAKEMKV_APP_BIN="/Applications/MakeMKV.app/Contents/MacOS/makemkvcon"
      if [ -x "$MAKEMKV_APP_BIN" ]; then
        mkdir -p "$BIN_DIR"
        ln -sf "$MAKEMKV_APP_BIN" "$BIN_DIR/makemkvcon"
        ok "makemkvcon nach $BIN_DIR/makemkvcon verlinkt."
      else
        err "makemkvcon wurde nach der Installation nicht unter"
        err "$MAKEMKV_APP_BIN gefunden. Bitte manuell pruefen (MakeMKV.app"
        err "einmal starten, damit es sich vollstaendig einrichtet) und"
        err "makemkvcon danach selbst nach $BIN_DIR verlinken."
      fi
    fi

    warn "Hinweis macOS: Geschwindigkeitsdrosselung bei Lesefehlern (Stufe 2"
    warn "der ddrescue-Eskalation in dvd-auto) gibt es unter macOS nicht - wird"
    warn "automatisch uebersprungen (direkt Stufe 1 -> ddrescue)."
    ;;

  *)
    err "Nicht unterstuetztes Betriebssystem: $OS"
    err "Bitte die Pakete aus der README manuell installieren."
    exit 1
    ;;
esac

step "Pruefe verfuegbare GPU-Beschleunigung fuer HandBrake..."
if [ "$OS" = "Darwin" ]; then
  ok "macOS erkannt - HandBrake nutzt VideoToolbox (Apple-eigene Hardware-Beschleunigung), sofern verfuegbar."
elif command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  ok "NVIDIA-GPU erkannt - NVENC wird automatisch verwendet."
elif command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -qi intel; then
  ok "Intel-GPU erkannt - QuickSync (falls von HandBrake unterstuetzt) wird automatisch versucht."
elif command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -Eqi 'amd|ati'; then
  ok "AMD-GPU erkannt - VCE (falls von HandBrake unterstuetzt) wird automatisch versucht."
else
  warn "Keine unterstuetzte GPU eindeutig erkannt - dvd-tools ermittelt den"
  warn "Encoder bei jedem Lauf automatisch neu und faellt notfalls auf"
  warn "Software-Encoding (x265, deutlich langsamer) zurueck."
fi
info "dvd-tools prueft dies bei jedem Encode live neu (siehe pick_hevc_encoder"
info "in lib/dvd-tools/platform.sh) - diese Meldung ist nur eine Momentaufnahme."

step "Installiere dvd-tools nach $BIN_DIR und $LIB_DIR..."
mkdir -p "$BIN_DIR" "$LIB_DIR"
cp -v "$SRC_DIR"/bin/* "$BIN_DIR/"
cp -v "$SRC_DIR"/lib/dvd-tools/* "$LIB_DIR/"
chmod +x "$BIN_DIR"/dvd-shrink "$BIN_DIR"/dvd-auto
ok "dvd-tools installiert."

echo
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  warn "$BIN_DIR ist nicht in deinem PATH. Fuege hinzu (z.B. in ~/.bashrc bzw. ~/.zshrc):"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
fi

echo
echo "Optional fuer automatische Titelerkennung (dvd-auto):"
echo "  mkdir -p ~/.config/dvd-tools"
echo "  cp $SRC_DIR/config.example ~/.config/dvd-tools/config"
echo "  # dann TMDB_API_KEY in der Datei eintragen"
echo
ok "Fertig."
