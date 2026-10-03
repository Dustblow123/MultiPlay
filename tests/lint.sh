#!/usr/bin/env sh
# Garde-fou : Godot 4.5 se bloque silencieusement (au lieu de signaler l'erreur)
# sur `var x := conteneur[clé]` quand le conteneur n'est pas typé. On impose un
# type explicite sur toute variable initialisée par un accès indexé.
set -e
cd "$(dirname "$0")/.."
hits=$(grep -rnE "var [A-Za-z_]+ := [^%\"']*\]\s*$" --include=*.gd . | grep -vE ":= \[|:= PackedVector2Array" || true)
if [ -n "$hits" ]; then
  echo "Inférence de type depuis un accès indexé (risque de blocage Godot) :"
  echo "$hits"
  exit 1
fi
echo "lint ok"
