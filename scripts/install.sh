#!/bin/bash
# Compile Dynamic Island Mac, l'installe dans /Applications et le lance.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

# Ferme la version en cours d'exécution avant de la remplacer.
pkill -x DynamicIslandMac 2>/dev/null || true
sleep 0.5

DEST="/Applications/Dynamic Island Mac.app"
rm -rf "$DEST"
ditto "build/Dynamic Island Mac.app" "$DEST"
open "$DEST"

echo "Dynamic Island Mac installé dans /Applications et lancé."
