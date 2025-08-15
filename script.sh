#!/usr/bin/env bash
set -e

# ========= Config =========
CONTENT_ROOT="content"
LOG_DIR="logs/validations"
PREVIEW_MODE=false
[[ "$1" == "--preview" ]] && PREVIEW_MODE=true

# Colores
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# Campos requeridos
REQ_FIELDS=("date:" "title:" "categories:" "resources:" "gender:" "estatura:" "edad:" "busto:" "cadera:" "cintura:" "ojos:" "habilidades:" "{{< measurements >}}")

# ========= Setup =========
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/validacion-$(date +%F_%H-%M-%S).log"
WARN=()

# Resumen por modelo (compatible bash 3.x: arrays paralelos)
WMODELS=()     # "Femeninos / Lucia Balegno"
WCOUNT=()      # cantidad de advertencias
WINDEX_OK=()   # 1/0 => index.md cumple
WPHOTOS_OK=()  # 1/0 => fotos cumplen

log(){ echo -e "$1" | tee -a "$LOG_FILE"; }

titlecase(){
  awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)};print}'
}
format_name(){ echo "$1" | tr '-' ' ' | titlecase; }

# Añadir advertencia y marcar estado por tipo (index|photos|other)
add_warn(){
  # $1 display_model, $2 mensaje, $3 tipo
  local m="$1"; local msg="$2"; local t="$3"; local idx=-1
  for i in "${!WMODELS[@]}"; do [[ "${WMODELS[$i]}" == "$m" ]] && idx=$i && break; done
  if [[ $idx -lt 0 ]]; then
    WMODELS+=("$m"); WCOUNT+=(0); WINDEX_OK+=(1); WPHOTOS_OK+=(1)
    idx=$((${#WMODELS[@]}-1))
  fi
  WCOUNT[$idx]=$(( ${WCOUNT[$idx]} + 1 ))
  case "$t" in
    index)  WINDEX_OK[$idx]=0 ;;
    photos) WPHOTOS_OK[$idx]=0 ;;
  esac
  WARN+=("$m: $msg")
}

# ========= Limpieza =========
log "${GREEN}🧹 Limpiando archivos basura...${NC}"
find "$CONTENT_ROOT" -type f \( -name ".DS_Store" -o -name "Thumbs.db" -o -name "._*" \) -delete

# ========= Autoformato de carpetas =========
log "${GREEN}📝 Corrigiendo nombres de carpetas...${NC}"
while IFS= read -r d; do
  base="$(basename "$d")"
  fixed="$(echo "$base" | tr '[:upper:]' '[:lower:]' | tr ' _' '-')"
  if [[ "$base" != "$fixed" ]]; then
    mv "$d" "$(dirname "$d")/$fixed"
    log "Renombrado: $base → $fixed"
  fi
done < <(find "$CONTENT_ROOT"/femeninos "$CONTENT_ROOT"/masculinos -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

# ========= Validaciones =========
log "${GREEN}🔍 Validando contenido...${NC}"
while IFS= read -r folder; do
  [[ $(basename "$folder") == "album" ]] && continue

  model_slug="$(basename "$folder")"
  category="$(basename "$(dirname "$folder")")"
  cat_title=$([ "$category" = "femeninos" ] && echo "Femeninos" || echo "Masculinos")
  display_model="$cat_title / $(format_name "$model_slug")"

  # cover: admite jpg/jpeg/png (esto cuenta para "fotos")
  cover=""
  for ext in jpg jpeg png; do
    [[ -f "$folder/cover.$ext" ]] && cover="$folder/cover.$ext" && break
  done
  if [[ -z "$cover" ]]; then
    add_warn "$display_model" "Falta cover (jpg/jpeg/png)" "photos"
  else
    if size=$(stat -f%z "$cover" 2>/dev/null || stat -c%s "$cover" 2>/dev/null); then
      (( size > 2000000 )) && add_warn "$display_model" "Cover >2MB. Considerar comprimir." "photos"
    fi
  fi

  # index.md o _index.md (estas cuentan para "index")
  if [[ -f "$folder/index.md" ]]; then
    for f in "${REQ_FIELDS[@]}"; do
      grep -q "$f" "$folder/index.md" || add_warn "$display_model" "Falta '$f' en index.md" "index"
    done
    grep -q 'categories: \["modelos"' "$folder/index.md" || add_warn "$display_model" "Categoría inusual en index.md" "index"
    grep -Eq ':[[:space:]]*$' "$folder/index.md" && add_warn "$display_model" "Campos vacíos en index.md" "index"
    grep -Eq 'resources:[\s\S]*cover\.(jpg|jpeg|png)' "$folder/index.md" || add_warn "$display_model" "Cover no referenciado en resources: en index.md" "index"
  elif [[ -f "$folder/_index.md" ]]; then
    grep -q "title:" "$folder/_index.md" || add_warn "$display_model" "Falta 'title' en _index.md" "index"
    grep -q "date:"  "$folder/_index.md"  || add_warn "$display_model" "Falta 'date' en _index.md" "index"
  else
    add_warn "$display_model" "Falta index.md o _index.md" "index"
  fi

  # Album: cantidad (<3 o >20), duplicados (fotos)
  if [[ -d "$folder/album" ]]; then
    photos=()
    while IFS= read -r p; do photos+=("$p"); done < <(find "$folder/album" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \))
    count=${#photos[@]}
    (( count < 3 ))  && add_warn "$display_model" "Muy pocas fotos en album ($count)" "photos"
    (( count > 20 )) && add_warn "$display_model" "Demasiadas fotos en album ($count)" "photos"
    if (( count > 0 )); then
      dups=$(printf "%s\n" "${photos[@]}" | xargs -n1 basename | sort | uniq -d)
      [[ -n "$dups" ]] && add_warn "$display_model" "Fotos duplicadas en album: $dups" "photos"
    fi
  else
    add_warn "$display_model" "Falta carpeta album" "photos"
  fi

  # Extensiones válidas en todo el folder (fotos)
  while IFS= read -r any; do
    ext="${any##*.}"
    [[ ! "$ext" =~ ^(jpg|jpeg|png)$ ]] && add_warn "$display_model" "Formato inválido: $(basename "$any")" "photos"
  done < <(find "$folder" -type f ! -name "*.md" -iname "*.*")
done < <(find "$CONTENT_ROOT"/femeninos "$CONTENT_ROOT"/masculinos -mindepth 1 -type d 2>/dev/null)

# ========= Advertencias (detalle, con color por género) =========
if [[ ${#WARN[@]} -gt 0 ]]; then
  echo
  log "${YELLOW}⚠️  Advertencias (detalle):${NC}"
  for w in "${WARN[@]}"; do
    # colorear categoría (Femeninos en rojo, Masculinos en azul) y el nombre del modelo con el mismo color
    cat_part="${w%%/*}"; rest="${w#*/ }"
    model_part="${rest%%:*}"; msg="${w#*: }"
    if [[ "$cat_part" == "Femeninos " || "$cat_part" == "Femeninos" ]]; then
      CATCOLOR="$RED"
    else
      CATCOLOR="$BLUE"
    fi
    echo -e " - ${CATCOLOR}${cat_part}${NC}/ ${CATCOLOR}${BOLD}${model_part}${NC}: ${YELLOW}${msg}${NC}" | tee -a "$LOG_FILE"
  done
fi

# ========= Resumen de advertencias por modelo (solo tabla, SIN colores en celdas) =========
if [[ ${#WMODELS[@]} -gt 0 ]]; then
  echo
  echo -e "${GREEN}📑 Resumen de advertencias por modelo:${NC}"
  printf "| %-40s | %-9s | %-5s |\n" "Modelo" "index.md" "Fotos"
  printf "|------------------------------------------|-----------|-------|\n"
  for i in "${!WMODELS[@]}"; do
    idx_status=$([ ${WINDEX_OK[$i]} -eq 1 ] && echo "OK" || echo "⚠️        ")
    pho_status=$([ ${WPHOTOS_OK[$i]} -eq 1 ] && echo "OK" || echo "⚠️    ")
    printf "| %-40s | %-9s | %-5s |\n" "${WMODELS[$i]}" "$idx_status" "$pho_status"
  done
fi

# ========= Build Hugo (opcional, sin cortar el flujo) =========
echo
log "${GREEN}🧹 Limpiando build...${NC}"
if command -v hugo &>/dev/null; then
  hugo --cleanDestinationDir || add_warn "Sistema" "Build Hugo falló" "other"
else
  add_warn "Sistema" "Hugo no está instalado" "other"
fi
$PREVIEW_MODE && command -v hugo &>/dev/null && hugo server && exit 0

# ========= Cambios (A/M/D) =========
CHANGED=$(git status --porcelain "$CONTENT_ROOT" 2>/dev/null || true)

FEM_A=() FEM_M=() FEM_D=()
MAS_A=() MAS_M=() MAS_D=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  status="${line:0:2}"
  path="${line:3}"
  [[ "$status" =~ ^R ]] && path="${path##*-> }" && status=" M"
  category=$(echo "$path" | cut -d'/' -f2)
  model=$(echo "$path" | cut -d'/' -f3)
  [[ "$category" != "femeninos" && "$category" != "masculinos" ]] && continue
  [[ -z "$model" ]] && continue
  case "$status" in
    "??"|A*) [[ "$category" == "femeninos" ]] && FEM_A+=("$model") || MAS_A+=("$model") ;;
    " D"|D*)  [[ "$category" == "femeninos" ]] && FEM_D+=("$model") || MAS_D+=("$model") ;;
    *)        [[ "$category" == "femeninos" ]] && FEM_M+=("$model") || MAS_M+=("$model") ;;
  esac
done <<< "$CHANGED"

uniq_list(){ printf "%s\n" "$@" | sort -u; }
FEM_A=($(uniq_list "${FEM_A[@]}")); FEM_M=($(uniq_list "${FEM_M[@]}")); FEM_D=($(uniq_list "${FEM_D[@]}"))
MAS_A=($(uniq_list "${MAS_A[@]}")); MAS_M=($(uniq_list "${MAS_M[@]}")); MAS_D=($(uniq_list "${MAS_D[@]}"))

# Totales de cambios (cantidad de modelos tocados por categoría)
TOTAL_F=$(( ${#FEM_A[@]} + ${#FEM_M[@]} + ${#FEM_D[@]} ))
TOTAL_M=$(( ${#MAS_A[@]} + ${#MAS_M[@]} + ${#MAS_D[@]} ))

# Totales en repo
COUNT_FEM=$(find "$CONTENT_ROOT/femeninos" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
COUNT_MAS=$(find "$CONTENT_ROOT/masculinos" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
COUNT_TOTAL=$(( COUNT_FEM + COUNT_MAS ))

# ========= Tabla de cambios (alineada; dejamos SIN color en celdas) =========
echo
echo -e "${GREEN}📋 Cambios detectados:${NC}"
printf "| %-11s | %-30s | %-30s | %-30s | %-5s |\n" "Categoría" "Agregados" "Modificados" "Eliminados" "Total"
printf "|------------|--------------------------------|--------------------------------|--------------------------------|-------|\n"

join_models(){ local out=""; for m in "$@"; do [[ -n "$m" ]] && out+="${out:+, }$(format_name "$m")"; done; [[ -z "$out" ]] && echo "—" || echo "$out"; }

fem_add="$(join_models "${FEM_A[@]}")"
fem_mod="$(join_models "${FEM_M[@]}")"
fem_del="$(join_models "${FEM_D[@]}")"; [[ "$fem_del" != "—" ]] && fem_del="❌ $fem_del"

mas_add="$(join_models "${MAS_A[@]}")"
mas_mod="$(join_models "${MAS_M[@]}")"
mas_del="$(join_models "${MAS_D[@]}")"; [[ "$mas_del" != "—" ]] && mas_del="❌ $mas_del"

printf "| %-10s | %-32s | %-32s | %-32s | %-5s |\n" "Femeninos" "$fem_add" "$fem_mod" "$fem_del" "$TOTAL_F"
printf "| %-10s | %-30s | %-32s | %-32s | %-5s |\n" "Masculinos" "$mas_add" "$mas_mod" "$mas_del" "$TOTAL_M"

echo
echo -e "👥 Totales en el repositorio: Femeninos: ${GREEN}$COUNT_FEM${NC} | Masculinos: ${GREEN}$COUNT_MAS${NC} | Total: ${GREEN}$COUNT_TOTAL${NC}"

# ========= Git simulado =========
ALL_MODELS=$(printf "%s\n" "${FEM_A[@]}" "${FEM_M[@]}" "${FEM_D[@]}" "${MAS_A[@]}" "${MAS_M[@]}" "${MAS_D[@]}" \
  | sort -u | while read -r n; do [[ -n "$n" ]] && format_name "$n"; done | paste -sd, -)
COMMIT_MSG="Actualización de ${ALL_MODELS:-contenido} - $(date +%Y-%m-%d)"

echo
echo "git add ."
echo "git commit -m \"$COMMIT_MSG\""
echo "git push origin main"
