#!/usr/bin/env bash
# Nemo peut passer une URI (file://), on la nettoie
input="${1#file://}"
output="${2#file://}"

if [[ "$input" != /* ]]; then
  input="$PWD/$input"
fi
if [[ "$output" != /* ]]; then
  output="$PWD/$output"
fi

# Création d'un dossier temporaire sûr
tmpdir=$(mktemp -d)
cd "$tmpdir" || exit 1

# 1. Extraction du groupe d'icônes (.ico) depuis l'exe
wrestool -x -t 14 "$input"

# 2. On cherche le premier fichier .ico extrait
ico_file=$(find . -name "*.ico" | head -n 1)

if [ -n "$ico_file" ]; then
  # 3. Extraction des images PNG depuis le fichier .ico
  icotool -x "$ico_file"
    
  # 4. On trie par taille via find et sort (sécurisé pour tous types de caractères)
  png_file=$(find . -maxdepth 1 -name "*.png" -printf "%s %p\n" 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)

  if [ -n "$png_file" ]; then
    # 5. On copie le résultat final pour Nemo
    cp "$png_file" "$output"
  fi
fi

# Nettoyage
rm -rf "$tmpdir"