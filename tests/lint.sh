#!/usr/bin/env sh
# Garde-fou : Godot 4.5 se bloque silencieusement (au lieu de signaler l'erreur)
# quand une variable `:=` est initialisée par une expression de type Variant :
# un accès indexé sur un conteneur non typé, seul ou dans un calcul.
# On impose un type explicite dans ces deux cas.
set -e
cd "$(dirname "$0")/.."
hits=$(grep -rnE "var [A-Za-z_]+ := [^%\"']*\]\s*$" --include=*.gd . | grep -vE ":= \[|:= PackedVector2Array" || true)
hits2=$(grep -rnE "var [A-Za-z_]+ := .*[]A-Za-z_)]\[[^]]*\] *[-+*/]" --include=*.gd . || true)
if [ -n "$hits$hits2" ]; then
  echo "Inférence de type depuis un accès indexé (risque de blocage Godot) :"
  echo "$hits"
  echo "$hits2"
  exit 1
fi
echo "lint ok"
