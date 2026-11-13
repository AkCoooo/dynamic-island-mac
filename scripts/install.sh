#!/bin/bash
# Compile Dynamic Island Mac, l'installe dans ~/Applications et le lance.
# ~/Applications ne demande pas de droits administrateur, et Launchpad comme Spotlight la voient.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

# Ferme la version en cours d'exécution avant de la remplacer.
pkill -x DynamicIslandMac 2>/dev/null || true
sleep 0.5

DEST="$HOME/Applications/Dynamic Island Mac.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "build/Dynamic Island Mac.app" "$DEST"
open "$DEST"

echo "Installé et lancé : ~/Applications/Dynamic Island Mac.app"
