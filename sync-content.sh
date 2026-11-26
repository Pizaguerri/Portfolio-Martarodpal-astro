
#!/bin/bash

# ============================================================
# sync-content.sh — Marta Rodriguez Palau
#
# Obsidian -> Astro -> Manifiesto -> R2 -> Cloudflare Cache
#         -> GitHub -> Workers
# ============================================================

set -Eeuo pipefail

# ------------------------------------------------------------
# CONFIGURACIÓN
# ------------------------------------------------------------

OBSIDIAN_SOURCE="/Users/pabloizaguerri/Library/Mobile Documents/iCloud~md~obsidian/Documents/Pizaguerri/03 Projectes/Portfolio-Martarodpal"

ASTRO_REPO="/Users/pabloizaguerri/Library/Mobile Documents/com~apple~CloudDocs/Coding Room/Astro-Portfolio-Martarodpal"

CONTENT_DEST="$ASTRO_REPO/src/content"
MANIFEST_FILE="src/data/media-manifest.json"
GENERATOR_FILE="src/scripts/generate-media-manifest.js"

R2_REMOTE="r2-marta:martarodpal-portfolio"

GIT_REMOTE="origin"
GIT_BRANCH="main"

PUBLIC_URL="https://martarodriguezpalau.org"
MEDIA_URL="https://media.martarodriguezpalau.org"

LOCAL_URL="http://localhost:4321"

CF_ZONE_ID="b466270a3f27f3d4226e8c9e7180c779"
CF_KEYCHAIN_SERVICE="cloudflare-marta-cache-purge"

PENDING_DIR="$HOME/Library/Application Support/MartaPortfolio"
PENDING_PURGE="$PENDING_DIR/pending-purge-urls.txt"

# ------------------------------------------------------------
# VARIABLES INTERNAS
# ------------------------------------------------------------

DEV_PID=""
TEMP_DIR=""
TOKEN=""

SYNC_NEEDED=false
R2_NEEDED=false
PURGE_NEEDED=false
HAS_GIT_CHANGES=false
NEEDS_DEPLOY=false

RSYNC_OPTIONS=(
  --exclude='.DS_Store'
  --omit-dir-times
)

# Solo se sincronizan imágenes.
# No se utiliza --delete-excluded.
R2_FILTERS=(
  --include '**.[jJ][pP][gG]'
  --include '**.[jJ][pP][eE][gG]'
  --include '**.[pP][nN][gG]'
  --include '**.[wW][eE][bB][pP]'
  --exclude '*'
)

# ------------------------------------------------------------
# FUNCIONES GENERALES
# ------------------------------------------------------------

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

    kill -TERM "$DEV_PID" 2>/dev/null || true
    wait "$DEV_PID" 2>/dev/null || true

    DEV_PID=""
  fi
}

cleanup() {
  stop_preview

  unset TOKEN

  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

check_git_changes() {
  local unexpected_changes

  unexpected_changes=$(git status --porcelain --untracked-files=all -- \
    . \
    ':(exclude)src/content' \
    ':(exclude)src/data/media-manifest.json' \
    ':(exclude)src/scripts/generate-media-manifest.js' \
    ':(exclude)sync-content.sh' \
    ':(exclude).gitignore' \
    ':(exclude)publicar-portfolio.command')

  if [[ -n "$unexpected_changes" ]]; then
    echo ""
    echo "ATENCIÓN: hay cambios ajenos al proceso editorial."
    echo ""
    printf '%s\n' "$unexpected_changes"
    echo ""
    echo "Revisa esos archivos antes de publicar."

    return 1
  fi

  return 0
}

check_git_index() {
  if ! git diff --cached --quiet; then
    echo ""
    echo "ERROR: hay cambios preparados en el índice de Git."
    echo "El sincronizador necesita un índice limpio."
    return 1
  fi

  return 0
}

# ------------------------------------------------------------
# PURGAS CLOUDFLARE
# ------------------------------------------------------------

purge_cloudflare() {
  local urls_file="$1"
  local total
  local offset=0
  local batch_file="$TEMP_DIR/purge-batch.json"
  local response_file="$TEMP_DIR/purge-response.json"
  local http_status

  total=$(wc -l < "$urls_file" | tr -d ' ')

  if [[ "$total" -eq 0 ]]; then
    echo "No hay URLs pendientes de purga."
    return 0
  fi

  TOKEN=$(security find-generic-password \
    -a "$USER" \
    -s "$CF_KEYCHAIN_SERVICE" \
    -w 2>/dev/null) \
    || error "No se encuentra el token de purga en el llavero."

  [[ -n "$TOKEN" ]] || error "El token de Cloudflare está vacío."

  echo ""
  echo "URLs pendientes de purga: $total"

  while [[ "$offset" -lt "$total" ]]; do
    local batch_count=$((total - offset))

    if [[ "$batch_count" -gt 30 ]]; then
      batch_count=30
    fi

    node --input-type=module - \
      "$urls_file" "$offset" "$batch_count" "$batch_file" <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';

const [file, offset, count, output] = process.argv.slice(2);

const urls = readFileSync(file, 'utf8')
  .split('\n')
  .filter(Boolean)
  .slice(Number(offset), Number(offset) + Number(count));

writeFileSync(output, JSON.stringify({ files: urls }));
NODE

    echo "Purgando lote: $((offset + 1)) - $((offset + batch_count)) de $total"

    http_status=$(curl -sS \
      -X POST \
      "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/purge_cache" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary "@$batch_file" \
      -o "$response_file" \
      -w '%{http_code}') \
      || error "No se pudo conectar con la API de Cloudflare."

    if [[ ! "$http_status" =~ ^2 ]]; then
      cat "$response_file"
      error "Cloudflare respondió con HTTP $http_status."
    fi

    node --input-type=module - "$response_file" <<'NODE'
import { readFileSync } from 'node:fs';

const result = JSON.parse(readFileSync(process.argv[2], 'utf8'));

if (!result.success) {
  console.error(JSON.stringify(result.errors ?? result, null, 2));
  process.exit(1);
}
NODE

    offset=$((offset + batch_count))
  done

  unset TOKEN

  echo "Purga de Cloudflare completada."
}

trap cleanup EXIT

# ------------------------------------------------------------
# VALIDACIONES INICIALES
# ------------------------------------------------------------

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

[[ -d "$OBSIDIAN_SOURCE" ]] || error "No se encuentra Obsidian."
[[ -d "$OBSIDIAN_SOURCE/bio" ]] || error "No se encuentra bio/."
[[ -d "$OBSIDIAN_SOURCE/work" ]] || error "No se encuentra work/."

[[ -d "$ASTRO_REPO" ]] || error "No se encuentra Astro."
[[ -d "$CONTENT_DEST" ]] || error "No se encuentra src/content."

[[ -f "$ASTRO_REPO/package.json" ]] || error "No se encuentra package.json."
[[ -f "$ASTRO_REPO/$GENERATOR_FILE" ]] || error "No se encuentra el generador."
[[ -f "$ASTRO_REPO/wrangler.jsonc" ]] || error "No se encuentra wrangler.jsonc."
[[ -f "$ASTRO_REPO/sync-content.sh" ]] || error "No se encuentra sync-content.sh."
[[ -f "$ASTRO_REPO/.gitignore" ]] || error "No se encuentra .gitignore."

for tool in rsync npm node curl git rclone security; do
  command -v "$tool" >/dev/null 2>&1 || error "No se encuentra: $tool."
done

[[ -x "$ASTRO_REPO/node_modules/.bin/wrangler" ]] \
  || error "No se encuentra Wrangler local."

cd "$ASTRO_REPO"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || error "No es un repositorio Git."

CURRENT_BRANCH=$(git branch --show-current)

[[ "$CURRENT_BRANCH" == "$GIT_BRANCH" ]] \
  || error "Rama incorrecta: $CURRENT_BRANCH."

git remote get-url "$GIT_REMOTE" >/dev/null 2>&1 \
  || error "No existe el remoto Git."

rclone listremotes | grep -Fxq "r2-marta:" \
  || error "No existe el remoto r2-marta."

rclone lsf "$R2_REMOTE" >/dev/null \
  || error "No se puede acceder al bucket R2."

mkdir -p "$PENDING_DIR"
touch "$PENDING_PURGE"

OBSIDIAN_FILE_COUNT=$(find "$OBSIDIAN_SOURCE" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')
BIO_FILE_COUNT=$(find "$OBSIDIAN_SOURCE/bio" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')
WORK_FILE_COUNT=$(find "$OBSIDIAN_SOURCE/work" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')

[[ "$OBSIDIAN_FILE_COUNT" -gt 0 ]] || error "Obsidian está vacío."
[[ "$BIO_FILE_COUNT" -gt 0 ]] || error "bio está vacío."
[[ "$WORK_FILE_COUNT" -gt 0 ]] || error "work está vacío."

echo "Archivos en Obsidian: $OBSIDIAN_FILE_COUNT"
echo "Archivos en bio:      $BIO_FILE_COUNT"
echo "Archivos en work:     $WORK_FILE_COUNT"

echo ""
echo "Validaciones iniciales completadas."

check_git_changes || exit 1
check_git_index || exit 1

TEMP_DIR=$(mktemp -d)

# ------------------------------------------------------------
# OBSIDIAN -> ASTRO
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo " SIMULACIÓN OBSIDIAN -> ASTRO"
echo "============================================================"
echo ""

RSYNC_RAW="$TEMP_DIR/rsync-raw.txt"
RSYNC_PREVIEW="$TEMP_DIR/rsync-preview.txt"

rsync -ani \
  --delete \
  --out-format='%i %n%L' \
  "${RSYNC_OPTIONS[@]}" \
  "$OBSIDIAN_SOURCE/" \
  "$CONTENT_DEST/" > "$RSYNC_RAW"

# Conserva solo líneas de cambios reales, no mensajes informativos.
grep -E '^(\*deleting|[<>ch.][^ ]{10} )' \
  "$RSYNC_RAW" > "$RSYNC_PREVIEW" || true

if [[ -s "$RSYNC_PREVIEW" ]]; then
  SYNC_NEEDED=true

  cat "$RSYNC_PREVIEW"

  echo ""

  if grep -q '^\*deleting ' "$RSYNC_PREVIEW"; then
    echo "ATENCIÓN: se eliminarán archivos de src/content."

    confirm "¿Confirmas las eliminaciones y la sincronización?" \
      || error "Sincronización cancelada."
  else
    confirm "¿Aplicar la sincronización de Obsidian a Astro?" \
      || error "Sincronización cancelada."
  fi
else
  echo "Obsidian y Astro ya están sincronizados."
fi

if [[ "$SYNC_NEEDED" == true ]]; then
  echo ""
  echo "Sincronizando contenido..."

  rsync -av --delete \
    "${RSYNC_OPTIONS[@]}" \
    "$OBSIDIAN_SOURCE/" \
    "$CONTENT_DEST/"

  echo "Contenido sincronizado."
fi

# ------------------------------------------------------------
# GENERACIÓN DEL MANIFIESTO
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo " GENERANDO MANIFIESTO"
echo "============================================================"
echo ""

npm run generate:media

[[ -f "$MANIFEST_FILE" ]] || error "No se ha generado el manifiesto."

node --input-type=module - "$MANIFEST_FILE" <<'NODE'
import { readFileSync } from 'node:fs';

const images = JSON.parse(readFileSync(process.argv[2], 'utf8'));

if (!Array.isArray(images)) {
  throw new Error('El manifiesto no contiene un array.');
}

const paths = new Set();

for (const image of images) {
  if (
    typeof image.path !== 'string' ||
    typeof image.sha256 !== 'string' ||
    !/^[a-f0-9]{64}$/i.test(image.sha256) ||
    !Number.isFinite(image.width) ||
    !Number.isFinite(image.height)
  ) {
    console.error('Entrada inválida en el manifiesto:', image);
    process.exit(1);
  }

  if (
    image.path.startsWith('/') ||
    image.path.split('/').includes('..') ||
    paths.has(image.path)
  ) {
    console.error('Ruta duplicada o insegura:', image.path);
    process.exit(1);
  }

  paths.add(image.path);
}

console.log(`Manifiesto válido: ${images.length} imágenes.`);
NODE

# ------------------------------------------------------------
# DETECCIÓN DE CAMBIOS GIT
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo " CAMBIOS EN GIT"
echo "============================================================"
echo ""

GIT_CHANGES=$(git status --porcelain --untracked-files=all -- \
  src/content/ \
  "$MANIFEST_FILE" \
  "$GENERATOR_FILE" \
  sync-content.sh \
  .gitignore)

EDITORIAL_CHANGES=$(git status --porcelain --untracked-files=all -- src/content/)

if [[ -n "$GIT_CHANGES" ]]; then
  HAS_GIT_CHANGES=true
  echo "Cambios que se pueden registrar:"
  printf '%s\n' "$GIT_CHANGES"
else
  echo "No hay cambios en los archivos gestionados por el sincronizador."
fi

if [[ -n "$EDITORIAL_CHANGES" ]]; then
  NEEDS_DEPLOY=true
  echo ""
  echo "Hay cambios en src/content: será necesario desplegar Workers."
else
  echo ""
  echo "No hay cambios editoriales en src/content."
fi

# ------------------------------------------------------------
# SIMULACIÓN REAL DE R2
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo " SIMULACIÓN DE SINCRONIZACIÓN R2"
echo "============================================================"
echo ""

R2_PREVIEW="$TEMP_DIR/r2-preview.txt"
R2_CURRENT_PURGES="$TEMP_DIR/r2-current-purges.txt"
PURGE_ALL="$TEMP_DIR/purge-all.txt"

# --checksum solicita comparar contenido mediante hashes cuando
# el backend proporciona un hash común.
# Los objetos excluidos por los filtros no se borran:
# no se utiliza --delete-excluded.

rclone sync "$CONTENT_DEST" "$R2_REMOTE" \
  "${R2_FILTERS[@]}" \
  --checksum \
  --dry-run \
  --combined "$R2_PREVIEW"

# Interpretamos las operaciones previstas por rclone.
# + = archivo nuevo
# * = archivo modificado
# - = archivo que se eliminará del destino
# ! = error

node --input-type=module - \
  "$R2_PREVIEW" "$R2_CURRENT_PURGES" "$MEDIA_URL" <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';

const [previewFile, outputFile, mediaUrl] = process.argv.slice(2);

const lines = readFileSync(previewFile, 'utf8')
  .split(/\r?\n/)
  .filter(Boolean);

const urls = new Set();
let changes = 0;

for (const line of lines) {
  const match = line.match(/^([-+*!=]) (.+)$/);

  if (!match) {
    throw new Error(`Formato inesperado en informe R2: ${line}`);
  }

  const [, action, path] = match;

  if (action === '!') {
    throw new Error(`Rclone informa de un error en: ${path}`);
  }

  if (action === '=') continue;

  if (!/\.(jpe?g|png|webp)$/i.test(path)) {
    throw new Error(`Operación fuera del filtro de imágenes: ${path}`);
  }

  changes++;

  const encodedPath = path
    .split('/')
    .map(segment => encodeURIComponent(segment))
    .join('/');

  urls.add(`${mediaUrl}/${encodedPath}`);
}

writeFileSync(
  outputFile,
  [...urls].sort().join('\n') + (urls.size ? '\n' : '')
);

console.log(`Operaciones de imágenes detectadas en R2: ${changes}`);
console.log(`URLs afectadas: ${urls.size}`);
NODE

if [[ -s "$R2_PREVIEW" ]]; then
  R2_NEEDED=true

  echo ""
  echo "Cambios previstos en R2:"
  cat "$R2_PREVIEW"
else
  echo "R2 no necesita cambios."
fi

# ------------------------------------------------------------
# RECUPERACIÓN DE PURGAS PENDIENTES
# ------------------------------------------------------------

cat "$PENDING_PURGE" "$R2_CURRENT_PURGES" \
  | sed '/^[[:space:]]*$/d' \
  | sort -u > "$PURGE_ALL"

PURGE_COUNT=$(wc -l < "$PURGE_ALL" | tr -d ' ')

if [[ "$PURGE_COUNT" -gt 0 ]]; then
  PURGE_NEEDED=true
fi

echo ""
echo "URLs pendientes de purga: $PURGE_COUNT"

# ------------------------------------------------------------
# PREVISUALIZACIÓN LOCAL
# ------------------------------------------------------------

echo ""

if confirm "¿Quieres previsualizar la web en local?"; then
  echo ""
  echo "Iniciando Astro..."

  "$ASTRO_REPO/node_modules/.bin/astro" dev --host 127.0.0.1 \
    > "$TEMP_DIR/astro-preview.log" 2>&1 &

  DEV_PID=$!

  SERVER_READY=false

  for i in {1..30}; do
    if ! kill -0 "$DEV_PID" 2>/dev/null; then
      cat "$TEMP_DIR/astro-preview.log"
      error "Astro no ha podido iniciar."
    fi

    if curl -fsS "$LOCAL_URL" >/dev/null 2>&1; then
      SERVER_READY=true
      break
    fi

    sleep 1
  done

  [[ "$SERVER_READY" == true ]] || {
    cat "$TEMP_DIR/astro-preview.log"
    error "Astro no ha respondido en 30 segundos."
  }

  open "$LOCAL_URL"

  echo ""
  echo "Previsualización abierta."
  echo "Pulsa Enter aquí en Terminal para continuar."

  read -r

  stop_preview
fi

# ------------------------------------------------------------
# RESUMEN Y CONFIRMACIÓN
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo " RESUMEN DE PUBLICACIÓN"
echo "============================================================"
echo ""

echo "Sincronización Obsidian -> Astro: $SYNC_NEEDED"
echo "Cambios en R2:                   $R2_NEEDED"
echo "URLs pendientes de purga:        $PURGE_COUNT"
echo "Cambios Git:                     $HAS_GIT_CHANGES"
echo "Despliegue Workers necesario:    $NEEDS_DEPLOY"

if [[ "$HAS_GIT_CHANGES" != true && \
      "$R2_NEEDED" != true && \
      "$PURGE_NEEDED" != true ]]; then

  echo ""
  echo "No hay cambios que publicar."
  exit 0
fi

echo ""
echo "Operaciones que se realizarán:"

[[ "$R2_NEEDED" != true ]] || echo "- Sincronizar imágenes en R2."
[[ "$PURGE_NEEDED" != true ]] || echo "- Purgar las URL afectadas en Cloudflare."
[[ "$HAS_GIT_CHANGES" != true ]] || echo "- Commit y push a GitHub."
[[ "$NEEDS_DEPLOY" != true ]] || echo "- Desplegar Cloudflare Workers."

echo ""

confirm "¿Confirmas la publicación?" \
  || error "Publicación cancelada. No se han aplicado cambios externos."

# Guardamos las purgas antes de modificar R2.
# Si la sincronización o la purga falla, quedan pendientes
# para el siguiente intento.

if [[ "$PURGE_COUNT" -gt 0 ]]; then
  cp "$PURGE_ALL" "$PENDING_PURGE"
fi

# ------------------------------------------------------------
# SINCRONIZACIÓN REAL R2
# ------------------------------------------------------------

if [[ "$R2_NEEDED" == true ]]; then
  echo ""
  echo "============================================================"
  echo " SINCRONIZANDO R2"
  echo "============================================================"
  echo ""

  rclone sync "$CONTENT_DEST" "$R2_REMOTE" \
    "${R2_FILTERS[@]}" \
    --checksum \
    --progress

  echo ""
  echo "Sincronización R2 completada."
fi

# ------------------------------------------------------------
# PURGA CLOUDFLARE
# ------------------------------------------------------------

if [[ "$PURGE_NEEDED" == true ]]; then
  echo ""
  echo "============================================================"
  echo " PURGANDO CACHÉ CLOUDFLARE"
  echo "============================================================"
  echo ""

  purge_cloudflare "$PENDING_PURGE"

  # Solo se vacía después de completar todos los lotes.
  : > "$PENDING_PURGE"
fi

# ------------------------------------------------------------
# GIT ADD, COMMIT Y PUSH
# ------------------------------------------------------------

if [[ "$HAS_GIT_CHANGES" == true ]]; then
  echo ""
  echo "============================================================"
  echo " REGISTRANDO CAMBIOS EN GIT"
  echo "============================================================"
  echo ""

  git add -A -- \
    src/content/ \
    "$MANIFEST_FILE" \
    "$GENERATOR_FILE" \
    sync-content.sh \
    .gitignore

  if ! git diff --cached --quiet; then
    DEFAULT_COMMIT_MESSAGE="Actualización editorial $(date '+%Y-%m-%d %H:%M')"

    echo "Introduce un mensaje para el commit."
    echo "Pulsa Enter para usar el mensaje automático."
    echo ""

    read -r -p "Mensaje: " COMMIT_MESSAGE

    if [[ -z "$COMMIT_MESSAGE" ]]; then
      COMMIT_MESSAGE="$DEFAULT_COMMIT_MESSAGE"
    fi

    git commit -m "$COMMIT_MESSAGE"
  fi

  echo ""
  echo "Enviando cambios a GitHub..."

  git push "$GIT_REMOTE" "$GIT_BRANCH"

  echo "GitHub actualizado."
fi

# ------------------------------------------------------------
# DESPLIEGUE WORKERS
# ------------------------------------------------------------

if [[ "$NEEDS_DEPLOY" == true ]]; then
  echo ""
  echo "============================================================"
  echo " DESPLEGANDO CLOUDFLARE WORKERS"
  echo "============================================================"
  echo ""

  npm run deploy

  echo "Workers desplegado."
fi

# ------------------------------------------------------------
# FINAL
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo " PUBLICACIÓN COMPLETADA"
echo "============================================================"
echo ""

echo "Obsidian -> Astro: sincronizado."
echo "Manifiesto: actualizado."
echo "R2: reconciliado."
echo "Caché Cloudflare: purgada cuando era necesario."

if [[ "$HAS_GIT_CHANGES" == true ]]; then
  echo "GitHub: actualizado."
else
  echo "GitHub: sin cambios."
fi

if [[ "$NEEDS_DEPLOY" == true ]]; then
  echo "Workers: desplegado."
else
  echo "Workers: no necesitaba despliegue."
fi

echo ""
echo "Web: $PUBLIC_URL"
echo ""

if confirm "¿Quieres abrir la web publicada?"; then
  open "$PUBLIC_URL"
fi

echo ""
echo "Proceso finalizado."
