#!/usr/bin/env bash
# Installiert dvd-tools nach ~/.local/bin und ~/.local/lib/dvd-tools
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LIB_DIR="$HOME/.local/lib/dvd-tools"

mkdir -p "$BIN_DIR" "$LIB_DIR"
cp -v "$SRC_DIR"/bin/* "$BIN_DIR/"
cp -v "$SRC_DIR"/lib/dvd-tools/* "$LIB_DIR/"
chmod +x "$BIN_DIR"/dvd-shrink "$BIN_DIR"/dvd-auto

echo
echo "Installiert. Stelle sicher, dass ~/.local/bin in deinem PATH ist:"
echo '  export PATH="$HOME/.local/bin:$PATH"'
echo
echo "Optional fuer automatische Titelerkennung (dvd-auto):"
echo "  mkdir -p ~/.config/dvd-tools"
echo "  cp $SRC_DIR/config.example ~/.config/dvd-tools/config"
echo "  # dann TMDB_API_KEY in der Datei eintragen"
