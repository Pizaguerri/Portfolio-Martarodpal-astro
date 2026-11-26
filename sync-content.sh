
#!/bin/bash

# ============================================================
# sync-content.sh — Marta Rodriguez Palau
#
# Flujo editorial y de publicación:
# Obsidian -> Astro -> Manifiesto -> R2 -> GitHub -> Workers
# ============================================================

set -Eeuo pipefail

# --- RUTAS ---

OBSIDIAN_SOURCE="/Users/pabloizaguerri/Library/Mobile Documents/iCloud~md~obsidian/Documents/Pizaguerri/03 Projectes/Portfolio-Martarodpal"

ASTRO_REPO="/Users/pabloizaguerri/Library/Mobile Documents/com~apple~CloudDocs/Coding Room/Astro-Portfolio-Martarodpal"

CONTENT_DEST="$ASTRO_REPO/src/content"
MANIFEST_FILE="src/data/media-manifest.json"
MANIFEST_SCRIPT="src/scripts/generate-media-manifest.js"

# --- R2 ---

R2_REMOTE="r2-marta:martarodpal-portfolio"

# --- GITHUB ---

GIT_REMOTE="origin"
GIT_BRANCH="main"

# --- PUBLICACIÓN ---

PUBLIC_URL="https://martarodriguezpalau.org"

# --- PREVISUALIZACIÓN ---

LOCAL_URL="http://localhost:4321"

# --- VARIABLES INTERNAS ---

DEV_PID=""
SYNC_PREVIEW=""
HAS_CONTENT_CHANGES=false

RSYNC_OPTIONS=(
  --exclude='.DS_Store'
  --omit-dir-times
)

# --- FUNCIONES ---

error() {
  echo ""
  echo "ERROR: $1"
  exit 1
}

confirm() {
  local answer
  read -r -p "$1 (s/n): " answer
  [[ "$answer" =~ ^[sS]$ ]]
}

stop_preview() {
  if [[ -n "$DEV_PID" ]]; then
    echo ""
    echo "Deteniendo servidor local..."

    pkill -TERM -P "$DEV_PID" 2>/dev/null || true
    kill "$DEV_PID" 2>/dev/null || true
    wait "$DEV_PID" 2>/dev/null || true

    DEV_PID=""
  fi
}

cleanup() {
  stop_preview

  if [[ -n "$SYNC_PREVIEW" ]]; then
    rm -f "$SYNC_PREVIEW"
  fi
}

# Comprueba que los cambios ajenos al contenido editorial
# no se mezclen accidentalmente en la publicación.
check_git_changes() {
  local unexpected_changes

  unexpected_changes=$(git status --porcelain --untracked-files=all -- \
    . \
    ':(exclude)src/content' \
    ':(exclude)src/data/media-manifest.json' \
    ':(exclude)publicar-portfolio.command' \
    ':(exclude)sync-content.sh' \
    ':(exclude).gitignore')

  if [[ -n "$unexpected_changes" ]]; then
    echo ""
    echo "ATENCIÓN: hay cambios ajenos al contenido editorial."
    echo ""
    echo "No se continuará para evitar mezclar cambios"
    echo "locales que no estén preparados para publicarse."
    echo ""

    printf '%s\n' "$unexpected_changes"

    echo ""
    echo "Revisa estos archivos antes de continuar."

    return 1
  fi

  return 0
}

# Comprueba que el índice de Git esté limpio.
check_git_index() {
  if ! git diff --cached --quiet; then
    echo ""
    echo "ERROR: hay cambios preparados en el índice de Git."
    echo ""
    echo "El sincronizador necesita un índice limpio."
    echo "Registra o retira esos cambios antes de continuar."
    return 1
  fi

  return 0
}

trap cleanup EXIT

# --- VALIDACIONES INICIALES ---

echo ""
echo "============================================================"
echo " PUBLICACIÓN DEL PORTFOLIO DE MARTA"
echo "============================================================"
echo ""

echo "Origen Obsidian: $OBSIDIAN_SOURCE"
echo "Destino Astro:   $CONTENT_DEST"
echo "Bucket R2:       $R2_REMOTE"
echo "Git:             $GIT_REMOTE / $GIT_BRANCH"
echo "Dominio:         $PUBLIC_URL"
echo ""

[[ -d "$OBSIDIAN_SOURCE" ]] || error "No se encuentra la carpeta de Obsidian."
[[ -d "$OBSIDIAN_SOURCE/bio" ]] || error "No se encuentra bio/ en Obsidian."
[[ -d "$OBSIDIAN_SOURCE/work" ]] || error "No se encuentra work/ en Obsidian."

[[ -d "$ASTRO_REPO" ]] || error "No se encuentra el repositorio Astro."
[[ -d "$CONTENT_DEST" ]] || error "No se encuentra src/content."

[[ -f "$ASTRO_REPO/package.json" ]] || error "No se encuentra package.json."
[[ -f "$ASTRO_REPO/$MANIFEST_SCRIPT" ]] || error "No se encuentra el generador del manifiesto."
[[ -f "$ASTRO_REPO/wrangler.jsonc" ]] || error "No se encuentra wrangler.jsonc."

OBSIDIAN_FILE_COUNT=$(find "$OBSIDIAN_SOURCE" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')
ASTRO_FILE_COUNT=$(find "$CONTENT_DEST" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')

[[ "$OBSIDIAN_FILE_COUNT" -gt 0 ]] || error "La carpeta de Obsidian está vacía."

BIO_FILE_COUNT=$(find "$OBSIDIAN_SOURCE/bio" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')
WORK_FILE_COUNT=$(find "$OBSIDIAN_SOURCE/work" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')

[[ "$BIO_FILE_COUNT" -gt 0 ]] || error "La colección bio está vacía."
[[ "$WORK_FILE_COUNT" -gt 0 ]] || error "La colección work está vacía."

cd "$ASTRO_REPO"

# Comprobar herramientas necesarias.
for tool in rsync npm node curl git rclone; do
  command -v "$tool" >/dev/null 2>&1 || error "No se encuentra la herramienta: $tool."
done

# Comprobar instalación local de Wrangler.
[[ -x "$ASTRO_REPO/node_modules/.bin/wrangler" ]] \
  || error "No se encuentra Wrangler en node_modules. Ejecuta npm install."

# Comprobar repositorio Git.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || error "La carpeta Astro no es un repositorio Git."

CURRENT_BRANCH=$(git branch --show-current)

[[ "$CURRENT_BRANCH" == "$GIT_BRANCH" ]] \
  || error "La rama actual es '$CURRENT_BRANCH', pero se esperaba '$GIT_BRANCH'."

git remote get-url "$GIT_REMOTE" >/dev/null 2>&1 \
  || error "No existe el remoto Git '$GIT_REMOTE'."

# Comprobar configuración local de rclone.
rclone listremotes | grep -Fxq "r2-marta:" \
  || error "No existe el remoto rclone 'r2-marta'. Configúralo antes de publicar."

# Comprobar acceso al bucket concreto.
rclone lsf "$R2_REMOTE" >/dev/null \
  || error "No se puede acceder al bucket R2 de Marta."

echo "Archivos en Obsidian: $OBSIDIAN_FILE_COUNT"
echo "Archivos en Astro:    $ASTRO_FILE_COUNT"
echo "Archivos en bio:      $BIO_FILE_COUNT"
echo "Archivos en work:     $WORK_FILE_COUNT"
echo ""
echo "Validaciones iniciales completadas."

# Evitar mezclar cambios ajenos al contenido editorial.
check_git_changes || exit 1

# No comenzar con cambios previamente preparados.
check_git_index || exit 1

# --- SIMULACIÓN DE SINCRONIZACIÓN ---

echo ""
echo "============================================================"
echo " SIMULACIÓN DE SINCRONIZACIÓN"
echo "============================================================"
echo ""

echo "Analizando cambios sin modificar archivos..."
echo ""

SYNC_PREVIEW=$(mktemp)

rsync -ani \
  --delete \
  --out-format='%i %n%L' \
  "${RSYNC_OPTIONS[@]}" \
  "$OBSIDIAN_SOURCE/" \
  "$CONTENT_DEST/" | tee "$SYNC_PREVIEW"

echo ""

SYNC_NEEDED=false

if [[ ! -s "$SYNC_PREVIEW" ]]; then
  echo "Obsidian y Astro ya están sincronizados."
  echo "No hay archivos que copiar, actualizar o eliminar."
else
  SYNC_NEEDED=true

  if grep -q '^\*deleting ' "$SYNC_PREVIEW"; then
    echo ""
    echo "ATENCIÓN: se eliminarán archivos de src/content."
    echo ""
    echo "Revisa cuidadosamente la lista anterior."
    echo ""

    if ! confirm "¿Confirmas las eliminaciones y la sincronización?"; then
      echo "Sincronización cancelada. No se ha modificado src/content."
      exit 0
    fi
  else
    echo "Se han detectado cambios que se sincronizarán en Astro."
    echo ""

    if ! confirm "¿Aplicar la sincronización de Obsidian a Astro?"; then
      echo "Sincronización cancelada."
      exit 0
    fi
  fi
fi

# --- SINCRONIZACIÓN REAL ---

if [[ "$SYNC_NEEDED" == true ]]; then
  echo ""
  echo "============================================================"
  echo " SINCRONIZANDO OBSIDIAN -> ASTRO"
  echo "============================================================"
  echo ""

  rsync -av --delete \
    "${RSYNC_OPTIONS[@]}" \
    "$OBSIDIAN_SOURCE/" \
    "$CONTENT_DEST/"

  echo ""
  echo "Contenido sincronizado."
else
  echo ""
  echo "No es necesaria ninguna sincronización de archivos."
fi

# --- GENERACIÓN DEL MANIFIESTO ---

echo ""
echo "============================================================"
echo " GENERANDO MANIFIESTO DE IMÁGENES"
echo "============================================================"
echo ""

npm run generate:media

echo ""
echo "Manifiesto actualizado."
echo ""

# --- DETECCIÓN DE CAMBIOS ---

echo "============================================================"
echo " COMPROBANDO CAMBIOS EDITORIALES"
echo "============================================================"
echo ""

CHANGED_CONTENT=$(git status --porcelain --untracked-files=all -- src/content/ "$MANIFEST_FILE")

if [[ -n "$CHANGED_CONTENT" ]]; then
  HAS_CONTENT_CHANGES=true

  echo "Se han detectado cambios en contenido o manifiesto:"
  echo ""
  printf '%s\n' "$CHANGED_CONTENT"
else
  HAS_CONTENT_CHANGES=false

  echo "No hay cambios editoriales respecto a Git."
  echo ""
  echo "No será necesario realizar una nueva publicación."
fi

# --- PREVISUALIZACIÓN LOCAL ---

echo ""

if confirm "¿Quieres previsualizar la web en local?"; then
  echo ""
  echo "Iniciando Astro..."
  echo "Se abrirá $LOCAL_URL"
  echo "Cuando termines, pulsa Ctrl+C para continuar."
  echo ""

  npm run dev > /tmp/astro-martarodpal-preview.log 2>&1 &
  DEV_PID=$!

  SERVER_READY=false

  for i in {1..30}; do
    if ! kill -0 "$DEV_PID" 2>/dev/null; then
      cat /tmp/astro-martarodpal-preview.log
      error "Astro no ha podido iniciar."
    fi

    if curl -fsS "$LOCAL_URL" >/dev/null 2>&1; then
      SERVER_READY=true
      break
    fi

    sleep 1
  done

  if [[ "$SERVER_READY" != true ]]; then
    cat /tmp/astro-martarodpal-preview.log
    error "Astro no ha respondido en 30 segundos."
  fi

  open "$LOCAL_URL"

  trap 'stop_preview' INT

  while [[ -n "$DEV_PID" ]] && kill -0 "$DEV_PID" 2>/dev/null; do
    sleep 1 || true
  done

  stop_preview
  trap - INT

  echo ""
  echo "Servidor local detenido."
fi

# --- SALIDA SI NO HAY CAMBIOS ---

if [[ "$HAS_CONTENT_CHANGES" != true ]]; then
  echo ""
  echo "============================================================"
  echo " NO HAY CAMBIOS QUE PUBLICAR"
  echo "============================================================"
  echo ""
  echo "No se ha subido nada a R2."
  echo "No se ha realizado ningún commit ni push a GitHub."
  echo "No se ha desplegado Cloudflare Workers."
  echo ""
  echo "Proceso finalizado."

  exit 0
fi

# --- CONFIRMACIÓN DE PUBLICACIÓN ---

echo ""
echo "============================================================"
echo " PUBLICACIÓN EXTERNA"
echo "============================================================"
echo ""

echo "Se realizarán las siguientes operaciones:"
echo ""
echo "1. Subir imágenes a Cloudflare R2."
echo "2. Registrar los cambios editoriales en Git."
echo "3. Enviar los cambios a GitHub."
echo "4. Construir y desplegar Cloudflare Workers."
echo ""
echo "Dominio: $PUBLIC_URL"
echo ""

if ! confirm "¿Confirmas la publicación completa?"; then
  echo "Publicación cancelada. Los cambios permanecen en local."
  exit 0
fi

# --- SUBIDA DE IMÁGENES A R2 ---

echo ""
echo "============================================================"
echo " SUBIENDO IMÁGENES A CLOUDFLARE R2"
echo "============================================================"
echo ""

rclone copy "$CONTENT_DEST" "$R2_REMOTE" \
  --include "**.[jJ][pP][gG]" \
  --include "**.[jJ][pP][eE][gG]" \
  --include "**.[pP][nN][gG]" \
  --include "**.[wW][eE][bB][pP]" \
  --exclude "*" \
  --no-check-dest \
  --progress

echo ""
echo "Imágenes subidas a R2."
echo "No se eliminan objetos existentes en el bucket."

# --- GIT ADD Y COMMIT ---

echo ""
echo "============================================================"
echo " REGISTRANDO CAMBIOS EN GIT"
echo "============================================================"
echo ""

git add -A -- src/content/ "$MANIFEST_FILE"

if git diff --cached --quiet; then
  echo "No hay cambios que registrar en Git."
else
  DEFAULT_COMMIT_MESSAGE="Actualización editorial $(date '+%Y-%m-%d %H:%M')"

  echo "Introduce un mensaje para el commit."
  echo "Pulsa Enter para utilizar el mensaje automático."
  echo ""

  read -r -p "Mensaje: " COMMIT_MESSAGE

  if [[ -z "$COMMIT_MESSAGE" ]]; then
    COMMIT_MESSAGE="$DEFAULT_COMMIT_MESSAGE"
  fi

  git commit -m "$COMMIT_MESSAGE"
fi

# --- PUSH A GITHUB ---

echo ""
echo "============================================================"
echo " ENVIANDO CAMBIOS A GITHUB"
echo "============================================================"
echo ""

git push "$GIT_REMOTE" "$GIT_BRANCH"

echo ""
echo "Cambios enviados a GitHub."

# --- DESPLIEGUE CLOUDFLARE WORKERS ---

echo ""
echo "============================================================"
echo " DESPLEGANDO CLOUDFLARE WORKERS"
echo "============================================================"
echo ""

npm run deploy

echo ""
echo "Despliegue completado."

# --- FINAL ---

echo ""
echo "============================================================"
echo " PUBLICACIÓN COMPLETADA"
echo "============================================================"
echo ""
echo "Obsidian -> Astro: completado."
echo "Manifiesto de imágenes: actualizado."
echo "Cloudflare R2: actualizado."
echo "GitHub: cambios enviados."
echo "Cloudflare Workers: desplegado."
echo ""
echo "Web: $PUBLIC_URL"
echo ""

if confirm "¿Quieres abrir la web publicada?"; then
  open "$PUBLIC_URL"
fi

echo ""
echo "Proceso finalizado."
