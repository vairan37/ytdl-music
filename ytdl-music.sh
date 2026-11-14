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
  echo -e "${CYAN}Usage :${NC} ytdl-music [--split | --no-split] <URL_YouTube>"
  echo ""
  echo "  --split      Découpe en pistes sans demander (chapitres ou tracklist de la description)"
  echo "  --no-split   Ne découpe jamais : un seul fichier"
  exit 1
}

# ── Fonctions utilitaires ─────────────────────────────────────────────────────

# Nom de fichier sans caractères interdits
safe() {
  printf '%s' "$1" | tr '/:*?"<>|\\' '_'
}

# "1:02:15" / "03:42" → secondes (échoue si l'horodatage est invalide)
ts_to_sec() {
  local h=0 m s parts
  IFS=: read -r -a parts <<< "$1"
  if [[ ${#parts[@]} -eq 3 ]]; then
    h=$((10#${parts[0]})); m=$((10#${parts[1]})); s=$((10#${parts[2]}))
    (( m < 60 )) || return 1
  else
    m=$((10#${parts[0]})); s=$((10#${parts[1]}))
  fi
  (( s < 60 )) || return 1
  echo $(( h * 3600 + m * 60 + s ))
}

# Millisecondes → "12.345" (pour ffmpeg)
ms_to_ff() {
  printf '%d.%03d' $(( $1 / 1000 )) $(( $1 % 1000 ))
}

# Millisecondes → "1:02:15" ou "3:42" (pour l'affichage)
ms_to_hms() {
  local t=$(( $1 / 1000 ))
  if (( t >= 3600 )); then
    printf '%d:%02d:%02d' $(( t / 3600 )) $(( t % 3600 / 60 )) $(( t % 60 ))
  else
    printf '%d:%02d' $(( t / 60 )) $(( t % 60 ))
  fi
}

# Secondes yt-dlp ("10.5", "62") → millisecondes, en bash pur
sec_to_ms() {
  local int=${1%%.*} frac=000
  [[ "$1" == *.* ]] && frac="${1#*.}000"
  [[ "$int" =~ ^[0-9]+$ ]] || return 1
  echo $(( 10#$int * 1000 + 10#${frac:0:3} ))
}

# Séparateurs autour d'un horodatage : espaces, - – — : | . , ~ •
SEP='([[:space:]]|-|–|—|:|\||\.|,|~|•)'
TS_RE='([0-9]{1,2}:)?[0-9]{1,3}:[0-9]{2}'

# Texte AVANT l'horodatage (« 1. Titre - 03:42 ») → « Titre »
clean_before() {
  printf '%s' "$1" | sed -E \
    -e 's/^[[:space:]]+//' \
    -e "s/(${SEP}|\\[|\\()+\$//" \
    -e 's/^#?[0-9]{1,3}([.)][[:space:]]*|$)//' \
    -e 's/^[0-9]{1,3}[[:space:]]+(-|–|—)[[:space:]]+//'
}

# Texte APRÈS l'horodatage (« ] - Titre ») → « Titre »
clean_after() {
  printf '%s' "$1" | sed -E \
    -e "s/^(${SEP}|\\]|\\))+//" \
    -e 's/^[0-9]{1,3}[.)][[:space:]]+//' \
    -e 's/[[:space:]]+$//'
}

# Pistes détectées (début en ms + titre)
T_START_MS=(); T_TITLE=()

# Extrait la tracklist d'une description (lignes « horodatage titre » ou « titre horodatage »)
parse_description() {
  local line ts before after title sec
  T_START_MS=(); T_TITLE=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ "$line" =~ (https?://|www\.) ]] && continue     # liens
    [[ "$line" =~ ^[[:space:]]*# ]] && continue         # hashtags
    [[ "$line" =~ $TS_RE ]] || continue
    ts=${BASH_REMATCH[0]}
    before=${line%%"$ts"*}
    after=${line#*"$ts"}
    # L'horodatage ne doit pas être collé à d'autres chiffres (ex. « 1234:56 »)
    [[ "$before" =~ [0-9]:?$ || "$after" =~ ^:?[0-9] ]] && continue
    sec=$(ts_to_sec "$ts") || continue
    before=$(clean_before "$before")
    after=$(clean_after "$after")
    if [[ -z "$before" ]]; then
      # Plage « 00:00 - 03:42 Titre » : on ignore l'horodatage de fin
      if [[ "$after" =~ ^($TS_RE)([^0-9]|$) ]]; then
        after=$(clean_after "${after#"${BASH_REMATCH[1]}"}")
      fi
      title=$after
    elif [[ -z "$after" ]]; then
      title=$before
    else
      continue   # horodatage au milieu d'une phrase : pas une piste
    fi
    [[ -z "$title" ]] && continue   # horodatage isolé, sans titre
    T_START_MS+=($(( sec * 1000 )))
    T_TITLE+=("$title")
  done <<< "$1"
}

# Vérifie que la tracklist est exploitable (≥ 2 pistes, début proche de 0, croissante)
validate_tracks() {
  local n=${#T_START_MS[@]} i
  (( n >= 2 )) || return 1
  (( T_START_MS[0] <= 10000 )) || return 1
  T_START_MS[0]=0   # quelques secondes d'écart au début : on part de 0
  for (( i = 1; i < n; i++ )); do
    (( T_START_MS[i] > T_START_MS[i-1] )) || return 1
  done
}

# Découpe <entrée> <sortie> <début_ms> [fin_ms] — copie sans ré-encodage, sinon MP3 qualité max
cut_track() {
  local range=(-ss "$(ms_to_ff "$3")")
  [[ -n "${4:-}" ]] && range+=(-to "$(ms_to_ff "$4")")
  if ffmpeg -y -loglevel error -i "$1" "${range[@]}" -map 0:a -c:a copy "$2" 2>/dev/null && [[ -s "$2" ]]; then
    return 0
  fi
  echo -e "${YELLOW}  Copie directe impossible, ré-encodage en MP3…${NC}"
  ffmpeg -y -loglevel error -i "$1" "${range[@]}" -map 0:a -c:a libmp3lame -q:a 0 "$2"
}

# Intègre la pochette carrée + tags ID3
# embed_tags <audio> <sortie> <titre> <artiste> [album] [piste "n/total"] [artiste de l'album]
embed_tags() {
  local extra=()
  [[ -n "${5:-}" ]] && extra+=(-metadata album="$5")
  [[ -n "${6:-}" ]] && extra+=(-metadata track="$6")
  [[ -n "${7:-}" ]] && extra+=(-metadata album_artist="$7")
  ffmpeg -y -loglevel error \
    -i "$1" \
    -i "$COVER" \
    -map 0:a \
    -map 1:v \
    -c:a copy \
    -c:v mjpeg \
    -id3v2_version 3 \
    -metadata title="$3" \
    -metadata artist="$4" \
    "${extra[@]}" \
    -metadata:s:v title="Album cover" \
    -metadata:s:v comment="Cover (front)" \
    -disposition:v:0 attached_pic \
    "$2"
}

# Sépare « Artiste - Titre » au premier séparateur ( - , – , — ) → SPLIT_ARTIST / SPLIT_TITLE
split_artist_title() {
  local t=$1 sep prefix best=""
  for sep in ' - ' ' – ' ' — '; do
    [[ "$t" == *"$sep"* ]] || continue
    prefix=${t%%"$sep"*}
    if [[ -z "$best" || ${#prefix} -lt ${#best} ]]; then
      best=$prefix; SPLIT_TITLE=${t#*"$sep"}
    fi
  done
  [[ -n "$best" && -n "$SPLIT_TITLE" ]] || return 1
  SPLIT_ARTIST=$best
}

# ── Arguments ─────────────────────────────────────────────────────────────────
SPLIT_MODE=ask   # ask | yes | no
URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --split)    SPLIT_MODE=yes ;;
    --no-split) SPLIT_MODE=no ;;
    -h|--help)  usage ;;
    -*)         echo -e "${RED}✗ Option inconnue : $1${NC}"; usage ;;
    *)          URL="$1" ;;
  esac
  shift
done
[[ -z "$URL" ]] && usage

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

# ── Détection des pistes : chapitres, sinon tracklist de la description ──────
SPLIT=no
if [[ "$SPLIT_MODE" != no ]]; then
  MARK='@@YTDL_MUSIC@@'
  INFO=$(yt-dlp --no-playlist \
    --print '%(chapters.:.start_time)#l' --print "$MARK" \
    --print '%(chapters.:.title)#l' --print "$MARK" \
    --print '%(description)s' "$URL" 2>/dev/null || true)

  if [[ "$INFO" == *"$MARK"*"$MARK"* ]]; then
    CH_STARTS=${INFO%%"$MARK"*}
    REST=${INFO#*"$MARK"$'\n'}
    CH_TITLES=${REST%%"$MARK"*}
    DESCRIPTION=${REST#*"$MARK"$'\n'}
  else
    CH_STARTS=""; CH_TITLES=""; DESCRIPTION=""
  fi

  SOURCE=""
  T_START_MS=(); T_TITLE=()
  mapfile -t _starts <<< "$CH_STARTS"
  mapfile -t _titles <<< "$CH_TITLES"
  for i in "${!_starts[@]}"; do
    ms=$(sec_to_ms "${_starts[i]}") || continue
    T_START_MS+=("$ms")
    T_TITLE+=("${_titles[i]:-Piste $(( i + 1 ))}")
  done
  if validate_tracks; then
    SOURCE="chapitres YouTube"
  elif [[ -n "$DESCRIPTION" && "$DESCRIPTION" != "NA" ]]; then
    parse_description "$DESCRIPTION"
    validate_tracks && SOURCE="tracklist de la description"
  fi

  if [[ -n "$SOURCE" ]]; then
    N=${#T_START_MS[@]}
    echo ""
    echo -e "${YELLOW}  ${N} pistes détectées (${SOURCE}) :${NC}"
    for (( i = 0; i < N; i++ )); do
      printf "    %02d  %8s  %s\n" $(( i + 1 )) "$(ms_to_hms "${T_START_MS[i]}")" "${T_TITLE[i]}"
    done
    echo ""
    if [[ "$SPLIT_MODE" == yes ]]; then
      SPLIT=yes
    else
      read -rp "$(echo -e "${GREEN}✂  Découper en ${N} pistes ? [O/n] : ${NC}")" ANSWER || true
      [[ "$ANSWER" =~ ^[nN] ]] || SPLIT=yes
    fi
  elif [[ "$SPLIT_MODE" == yes ]]; then
    echo -e "${YELLOW}  Aucun chapitre ni tracklist exploitable : un seul fichier.${NC}"
  fi
fi

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

OUTPUT_DIR="${HOME}/Musique"

# La dernière piste doit commencer avant la fin de l'audio
if [[ "$SPLIT" == yes ]] && command -v ffprobe &>/dev/null; then
  DURATION=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$AUDIO" || true)
  DURATION_MS=$(sec_to_ms "$DURATION" || echo 0)
  if (( DURATION_MS > 0 && T_START_MS[N-1] >= DURATION_MS )); then
    echo -e "${YELLOW}  La tracklist dépasse la durée de l'audio ($(ms_to_hms "$DURATION_MS")) : un seul fichier.${NC}"
    SPLIT=no
  fi
fi

if [[ "$SPLIT" == yes ]]; then
  # ── Mode découpage : métadonnées de l'album ──────────────────────────────
  echo ""
  echo -e "${YELLOW}  Métadonnées de l'album (Entrée pour valider, ou tape pour modifier)${NC}"
  echo ""
  read -rp "$(echo -e "${GREEN}💿 Album   [${YT_TITLE}] : ${NC}")" ALBUM || true
  read -rp "$(echo -e "${GREEN}🎤 Artiste [${YT_ARTIST}] : ${NC}")" ARTIST || true
  [[ -z "$ALBUM" ]]  && ALBUM="${YT_TITLE:-Unknown Album}"
  [[ -z "$ARTIST" ]] && ARTIST="${YT_ARTIST:-Unknown Artist}"

  # Titres au format « Artiste - Titre » ? On propose d'extraire l'artiste par piste
  PER_TRACK_ARTIST=no
  WITH_SEP=0
  for t in "${T_TITLE[@]}"; do
    split_artist_title "$t" && WITH_SEP=$(( WITH_SEP + 1 ))
  done
  if (( WITH_SEP > 0 )); then
    echo ""
    echo -e "${YELLOW}  ${WITH_SEP}/${N} titres ressemblent à « Artiste - Titre ».${NC}"
    read -rp "$(echo -e "${GREEN}🎤 Extraire l'artiste de chaque piste ? [O/n] : ${NC}")" ANSWER || true
    [[ "$ANSWER" =~ ^[nN] ]] || PER_TRACK_ARTIST=yes
  fi

  ALBUM_DIR="${OUTPUT_DIR}/$(safe "${ARTIST} - ${ALBUM}")"
  mkdir -p "$ALBUM_DIR"

  echo -e "${CYAN}▶ Découpage et intégration de la couverture et des métadonnées…${NC}"
  for (( i = 0; i < N; i++ )); do
    NUM=$(printf '%02d' $(( i + 1 )))
    TRACK_TITLE=${T_TITLE[i]}
    TRACK_ARTIST=$ARTIST
    if [[ "$PER_TRACK_ARTIST" == yes ]] && split_artist_title "$TRACK_TITLE"; then
      TRACK_ARTIST=$SPLIT_ARTIST
      TRACK_TITLE=$SPLIT_TITLE
    fi
    PART="$TMP/part_${NUM}.mp3"
    if (( i + 1 < N )); then
      cut_track "$AUDIO" "$PART" "${T_START_MS[i]}" "${T_START_MS[i+1]}"
    else
      cut_track "$AUDIO" "$PART" "${T_START_MS[i]}"   # jusqu'à la fin de l'audio
    fi
    FINAL="${ALBUM_DIR}/${NUM} - $(safe "$TRACK_TITLE").mp3"
    embed_tags "$PART" "$FINAL" "$TRACK_TITLE" "$TRACK_ARTIST" "$ALBUM" "$(( i + 1 ))/${N}" "$ARTIST"
    echo -e "  ${GREEN}✔${NC} ${NUM} - ${TRACK_TITLE}"
  done

  echo ""
  echo -e "${GREEN}✔ ${N} pistes créées dans :${NC} $ALBUM_DIR"
  exit 0
fi

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
SAFE_NAME=$(safe "${ARTIST} - ${TITLE}")
mkdir -p "$OUTPUT_DIR"
FINAL="${OUTPUT_DIR}/${SAFE_NAME}.mp3"

# ── Intégration cover + métadonnées via ffmpeg ────────────────────────────────
echo -e "${CYAN}▶ Intégration de la couverture et des métadonnées…${NC}"
embed_tags "$AUDIO" "$FINAL" "$TITLE" "$ARTIST"

echo ""
echo -e "${GREEN}✔ Fichier créé :${NC} $FINAL"
