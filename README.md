# ytdl-music

Télécharge l'audio d'une vidéo **YouTube, SoundCloud, ou tout site supporté par yt-dlp** en MP3, avec la miniature recadrée en carré intégrée comme pochette et les métadonnées (titre, artiste) récupérées automatiquement.

---

## Dépendances

| Outil | Rôle |
|---|---|
| `yt-dlp` | Téléchargement audio + métadonnées + miniature |
| `ffmpeg` | Intégration de la pochette et des tags ID3 |
| `ImageMagick` | Recadrage de la miniature en carré |

### Fedora

```bash
# Activer RPM Fusion (nécessaire pour ffmpeg)
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

sudo dnf install ffmpeg ImageMagick yt-dlp
```

### Debian / Ubuntu

```bash
sudo apt install ffmpeg imagemagick

# yt-dlp : la version apt est souvent obsolète, préférer pipx
sudo apt install pipx && pipx install yt-dlp
```

### Arch Linux

```bash
sudo pacman -S ffmpeg imagemagick yt-dlp
```

### macOS (Homebrew)

```bash
brew install ffmpeg imagemagick yt-dlp
```

---

## Installation du script

```bash
# Rendre le script exécutable
chmod +x ytdl-music.sh

# Le déplacer dans le PATH pour l'utiliser comme commande globale
sudo mv ytdl-music.sh /usr/local/bin/ytdl-music
```

---

## Utilisation

```bash
ytdl-music [--split | --no-split | --tracklist FICHIER] [--comments N|all] "<URL>"
```

> ⚠️ **Mets toujours l'URL entre guillemets.** Une URL YouTube contient souvent des `&` (`…&list=…&t=…`) : sans guillemets, bash coupe la commande à chaque `&` et lance le script en arrière-plan avec une URL tronquée.

| Option | Effet |
|---|---|
| *(aucune)* | Si des pistes sont détectées, affiche la tracklist et demande `Découper en N pistes ? [O/n]` |
| `--split` | Découpe sans demander. Si rien n'est détecté, propose de **coller une tracklist** au clavier |
| `--no-split` | Ne cherche pas de pistes : toujours un seul fichier (comportement historique) |
| `--tracklist FICHIER` | Découpe selon la tracklist du fichier (une ligne `00:00 Titre` par piste), sans rien chercher en ligne |
| `--comments N` | Cherche une tracklist dans les N commentaires les plus populaires (50 par défaut), quelle que soit la durée de la vidéo |
| `--comments all` | Lit **tous** les commentaires : retrouve une tracklist postée par un fan même peu likée (≈ 1 min pour 4 000 commentaires) |

### Exemples

```bash
# YouTube
ytdl-music "https://www.youtube.com/watch?v=xxxxx"

# SoundCloud
ytdl-music "https://soundcloud.com/artiste/titre"

# Bandcamp, Vimeo, Twitter, et +1000 autres sites supportés par yt-dlp...
ytdl-music "https://bandcamp.com/..."
```

### Déroulement

1. Le script récupère les métadonnées (titre, artiste) automatiquement
2. Télécharge l'audio en MP3 qualité maximale
3. Recadre la miniature en carré centré
4. Affiche les métadonnées pré-remplies — **Entrée pour valider, ou tape pour modifier**
5. Intègre la pochette et les tags dans le fichier final

```
▶ Récupération des métadonnées YouTube…
▶ Téléchargement de l'audio…
▶ Recadrage de la miniature en carré…

  Métadonnées récupérées automatiquement (Entrée pour valider, ou tape pour modifier)

🎵 Titre   [Bohemian Rhapsody] :
🎤 Artiste [Queen] :

✔ Fichier créé : ~/Musique/Queen - Bohemian Rhapsody.mp3
```

---

## Découpage en pistes (albums, mixes, compilations)

Quand une vidéo contient plusieurs morceaux, le script peut la découper en un MP3 par piste. Les pistes sont cherchées dans cet ordre :

1. les **chapitres YouTube** ;
2. une **tracklist horodatée dans la description** ;
3. une **tracklist postée en commentaire** : parmi les 50 commentaires les plus populaires (ou plus avec `--comments`), le script garde celui qui donne la tracklist valide la plus longue ; à égalité, le plus populaire. Son auteur est affiché. Cette recherche prend quelques secondes, elle n'est donc faite que pour les vidéos de **8 min ou plus**, ou avec `--split` / `--comments` ;
4. avec `--split`, si rien n'a été trouvé : **saisie manuelle**. Colle la tracklist (une piste par ligne) et termine par une ligne vide.

### Vidéos sans chapitres ni tracklist (freestyles, sessions type Grünt…)

Ces vidéos s'enchaînent sans blanc entre les morceaux : impossible de les découper automatiquement à partir du son. Il faut donc des horodatages venus d'ailleurs :

```bash
# Le script fouille les 50 commentaires les plus populaires
ytdl-music "<URL>"

# Tracklist postée plus bas dans les commentaires : on les lit tous (~1 min)
ytdl-music --comments all "<URL>"

# Rien en commentaire : --split propose de coller la tracklist
ytdl-music --split "<URL>"

# Ou tracklist préparée dans un fichier
cat > grunt.txt <<'EOF'
0:00 Rappeur A
4:10 Rappeur B
9:30 Rappeur C
EOF
ytdl-music --tracklist grunt.txt "<URL>"
```

Exemple réel : sur un Grünt de 28 min à ~6 000 commentaires, la tracklist d'un fan n'arrivait qu'autour de la 370ᵉ place. `--comments all` l'a trouvée en ~1 min, téléchargement et découpage compris.

L'audio n'est téléchargé qu'une fois, puis découpé avec ffmpeg (copie directe sans ré-encodage, ou ré-encodage MP3 qualité max si la copie échoue). La dernière piste va jusqu'à la fin de l'audio.

### Formats de tracklist reconnus

```
00:00 Intro                      ← mm:ss en début de ligne
03:42 - Deuxième morceau         ← séparateurs « - », « – », « — », « : », « | »…
[07:15] Troisième morceau        ← horodatage entre crochets ou parenthèses
4. 1:02:15 Quatrième morceau     ← h:mm:ss, numérotation « 4. » ou « 4) » devant
Cinquième morceau - 1:10:00      ← horodatage en fin de ligne
00:00 - 03:42 Intro              ← plage : seul le début compte
0:00 A 3:12 B 6:40 C             ← plusieurs pistes sur une ligne (fréquent en commentaire)
```

Sont ignorés : les lignes contenant un lien, les lignes de hashtags, un horodatage seul sur sa ligne et un horodatage au milieu d'une phrase (« enregistré à 21:30 à Paris »).

La tracklist n'est proposée que si elle contient **au moins 2 pistes**, que la première commence **dans les 10 premières secondes** (elle est alors ramenée à 0:00) et que les horodatages sont **strictement croissants**. Sinon, le script télécharge un seul fichier comme avant.

### Exemple

```
▶ Récupération des métadonnées YouTube…

  3 pistes détectées (tracklist de la description) :
    01      0:00  Daft Punk - One More Time
    02      5:20  Daft Punk - Aerodynamic
    03      8:52  Daft Punk - Digital Love

✂  Découper en 3 pistes ? [O/n] :
▶ Téléchargement de l'audio…
▶ Recadrage de la miniature en carré…

  Métadonnées de l'album (Entrée pour valider, ou tape pour modifier)

💿 Album   [Discovery (Full Album)] : Discovery
🎤 Artiste [Daft Punk] :

  3/3 titres ressemblent à « Artiste - Titre ».
🎤 Extraire l'artiste de chaque piste ? [O/n] :
▶ Découpage et intégration de la couverture et des métadonnées…
  ✔ 01 - One More Time
  ✔ 02 - Aerodynamic
  ✔ 03 - Digital Love

✔ 3 pistes créées dans : ~/Musique/Daft Punk - Discovery
```

Chaque piste reçoit la pochette carrée et les tags titre, artiste, album, artiste de l'album et numéro de piste (`1/3`, `2/3`…).

Si des titres sont au format `Artiste - Titre` (compilations, mixes de DJ), le script propose d'en extraire l'artiste piste par piste. Les pistes sans séparateur gardent l'artiste saisi pour l'album.

### Limites

- La détection repose sur des heuristiques : une description mal formatée peut être ignorée, ou plus rarement une ligne parasite peut être prise pour une piste. La tracklist est toujours affichée avant de découper ; `--no-split` permet de passer outre.
- Les horodatages des descriptions sont à la seconde près, et parfois approximatifs : les coupures héritent de ces imprécisions.
- En copie directe, la coupure se fait à la trame MP3 près (~26 ms).
- Si la tracklist dépasse la durée réelle de l'audio, le script abandonne le découpage et crée un seul fichier.
- Les commentaires ne sont lus que sur YouTube, triés par popularité, **sans les réponses** : une tracklist postée en réponse à un autre commentaire n'est pas vue, même avec `--comments all`. Dans ce cas, utilise `--split` ou `--tracklist`.
- `--comments all` dépend de la taille de la vidéo : environ 1 min pour quelques milliers de commentaires, beaucoup plus pour une vidéo très populaire.
- Plusieurs pistes sur une seule ligne ne sont reconnues que si la ligne commence par un horodatage (`0:00 A 3:12 B`), pas au format `A 0:00 B 3:12`.
- Pour la saisie manuelle, la tracklist se termine à la première ligne vide : retire les lignes vides au milieu avant de coller.

---

## Fichiers de sortie

Les MP3 sont sauvegardés dans **`~/Musique/`** avec le format :

```
Artiste - Titre.mp3
```

En mode découpage, les pistes sont rangées dans un dossier par album :

```
~/Musique/Artiste - Album/
├── 01 - Titre.mp3
├── 02 - Titre.mp3
└── …
```

La pochette est intégrée directement dans le fichier (visible dans VLC, Rhythmbox, sur mobile, etc.).

---

## Sites supportés

`yt-dlp` supporte plus de 1000 sites. Quelques exemples :

- YouTube / YouTube Music
- SoundCloud
- Bandcamp
- Deezer (previews)
- Vimeo
- Twitter / X
- Instagram
- Twitch (VODs)

Liste complète : https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md