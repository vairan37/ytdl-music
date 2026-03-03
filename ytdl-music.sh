#!/usr/bin/env bash
# ytdl-music — Télécharge l'audio d'une vidéo YouTube + miniature carrée + métadonnées
# Dépendances : yt-dlp, ffmpeg, ImageMagick (convert)

set -e

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

check_deps() {
  local missing=()
  for cmd in yt-dlp ffmpeg convert; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RED}✗ Dépendances manquantes : ${missing[*]}${NC}"
    echo "  Installe-les avec :"
    echo "    sudo dnf install ffmpeg ImageMagick   # Fedora"
    exit 1
  fi
}

usage() {
  echo -e "${CYAN}Usage :${NC} ytdl-music <URL_YouTube>"
  exit 1
}

[[ $# -lt 1 ]] && usage
URL="$1"

check_deps

# ── Dossier de travail temporaire ─────────────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo -e "${CYAN}▶ Récupération des métadonnées YouTube…${NC}"
YT_TITLE=$(yt-dlp --no-playlist --print "%(title)s" "$URL" 2>/dev/null || true)
YT_ARTIST=$(yt-dlp --no-playlist --print "%(artist)s" "$URL" 2>/dev/null || true)
# "artist" peut être vide sur les vidéos normales, on essaie "uploader" en fallback
[[ -z "$YT_ARTIST" || "$YT_ARTIST" == "NA" ]] && \
  YT_ARTIST=$(yt-dlp --no-playlist --print "%(uploader)s" "$URL" 2>/dev/null || true)

echo -e "${CYAN}▶ Téléchargement de l'audio…${NC}"
yt-dlp \
  --extract-audio \
  --audio-format mp3 \
  --audio-quality 0 \
  --write-thumbnail \
  --convert-thumbnails jpg \
  --no-playlist \
  -o "$TMP/audio.%(ext)s" \
  "$URL"

# ── Fichiers produits ─────────────────────────────────────────────────────────
AUDIO="$TMP/audio.mp3"
THUMB=$(find "$TMP" -name "*.jpg" | head -1)

[[ -z "$THUMB" ]] && { echo -e "${RED}✗ Impossible de récupérer la miniature.${NC}"; exit 1; }

# ── Miniature carrée (crop centré) ────────────────────────────────────────────
COVER="$TMP/cover.jpg"
echo -e "${CYAN}▶ Recadrage de la miniature en carré…${NC}"
convert "$THUMB" \
  -gravity Center \
  -thumbnail "$(identify -format '%[fx:min(w,h)]x%[fx:min(w,h)]' "$THUMB")^" \
  -extent "$(identify -format '%[fx:min(w,h)]x%[fx:min(w,h)]' "$THUMB")" \
  "$COVER"

# ── Métadonnées (pré-remplies, modifiables) ───────────────────────────────────
echo ""
echo -e "${YELLOW}  Métadonnées récupérées automatiquement (Entrée pour valider, ou tape pour modifier)${NC}"
echo ""
read -rp "$(echo -e ${GREEN}🎵 Titre   [${YT_TITLE}] : ${NC})" TITLE
read -rp "$(echo -e ${GREEN}🎤 Artiste [${YT_ARTIST}] : ${NC})" ARTIST

# Si l'utilisateur n'a rien tapé, on garde la valeur automatique
[[ -z "$TITLE" ]]  && TITLE="${YT_TITLE:-Unknown Title}"
[[ -z "$ARTIST" ]] && ARTIST="${YT_ARTIST:-Unknown Artist}"

# ── Nom de fichier final ──────────────────────────────────────────────────────
SAFE_NAME=$(echo "${ARTIST} - ${TITLE}" | tr '/:*?"<>|\\' '_')
OUTPUT_DIR="${HOME}/Musique"
mkdir -p "$OUTPUT_DIR"
FINAL="${OUTPUT_DIR}/${SAFE_NAME}.mp3"

# ── Intégration cover + métadonnées via ffmpeg ────────────────────────────────
echo -e "${CYAN}▶ Intégration de la couverture et des métadonnées…${NC}"
ffmpeg -y -loglevel error \
  -i "$AUDIO" \
  -i "$COVER" \
  -map 0:a \
  -map 1:v \
  -c:a copy \
  -c:v mjpeg \
  -id3v2_version 3 \
  -metadata title="$TITLE" \
  -metadata artist="$ARTIST" \
  -metadata:s:v title="Album cover" \
  -metadata:s:v comment="Cover (front)" \
  -disposition:v:0 attached_pic \
  "$FINAL"

echo ""
echo -e "${GREEN}✔ Fichier créé :${NC} $FINAL"
