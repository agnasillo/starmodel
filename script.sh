#!/bin/bash

PREVIEW=false
if [[ "$1" == "--preview" ]]; then
  PREVIEW=true
fi

echo "🧹 Limpiando archivos basura..."
find . -name "*.DS_Store" -type f -delete

echo "📝 Corrigiendo nombres de carpetas..."
find content -type d | while read -r dir; do
  newdir=$(echo "$dir" | sed 's/ /-/g' | tr '[:upper:]' '[:lower:]')
  [[ "$dir" != "$newdir" ]] && mv "$dir" "$newdir"
done

echo "🔍 Validando contenido..."
mkdir -p logs
validation_log="logs/validations/$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$validation_log")"

warn=false
find content -type f -name "index.md" | while read -r file; do
  empty_fields=false
  if grep -q "title: \"\"" "$file"; then
    echo " - Campos vacíos en $file" | tee -a "$validation_log"
    warn=true
  fi
  cover_path=$(grep "^cover:" "$file" | awk '{print $2}')
  if [[ -n "$cover_path" && -f "$(dirname "$file")/$cover_path" ]]; then
    size_mb=$(du -m "$(dirname "$file")/$cover_path" | cut -f1)
    [[ "$size_mb" -gt 2 ]] && echo " - Cover grande en $(dirname "$file") (>2MB). Comprimir la imagen." | tee -a "$validation_log"
  fi
  fotos_count=$(find "$(dirname "$file")" -type f \( -iname "*.jpg" -o -iname "*.png" \) | wc -l)
  if [[ "$fotos_count" -lt 3 ]]; then
    echo " - Menos de 3 fotos en $(dirname "$file")" | tee -a "$validation_log"
  fi
done

[[ "$warn" == true ]] && echo "⚠️ Advertencias registradas en $validation_log"

echo "🧹 Limpiando build..."
rm -rf public

total_models=$(find content -mindepth 2 -maxdepth 2 -type d | wc -l)

fem_add="-"
fem_mod="-"
fem_del="-"
fem_total=$(find content/femeninos -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
masc_add="-"
masc_mod="-"
masc_del="-"
masc_total=$(find content/masculinos -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

printf "\n📋 Cambios detectados:\n"
printf "| %-10s | %-9s | %-11s | %-10s | %-5s |\n" "Categoría" "Agregados" "Modificados" "Eliminados" "Total"
printf "|------------|-----------|-------------|------------|-------|\n"
printf "| %-10s | %-9s | %-11s | %-10s | %-5s |\n" "Femeninos" "$fem_add" "$fem_mod" "$fem_del" "$fem_total"
printf "| %-10s | %-9s | %-11s | %-10s | %-5s |\n" "Masculinos" "$masc_add" "$masc_mod" "$masc_del" "$masc_total"

echo -e "\n📦 Total de modelos: $total_models"

git add .
git commit -m "Actualización de contenido - $(date +%F)"
echo git push origin main

if $PREVIEW; then
  echo "🌐 Generando preview con Hugo..."
  hugo server -D
fi
