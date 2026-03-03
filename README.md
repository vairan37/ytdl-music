# ytdl-music

Télécharge l'audio d'une vidéo **YouTube, SoundCloud, ou tout site supporté par yt-dlp** en MP3, avec la miniature recadrée en carré intégrée comme pochette et les métadonnées (titre, artiste) récupérées automatiquement.

---

## Dépendances

| Outil | Rôle |
|---|---|
| `yt-dlp` | Téléchargement audio + métadonnées + miniature |
| `ffmpeg` | Intégration de la pochette et des tags ID3 |
| `ImageMagick` | Recadrage de la miniature en carré |

### Installation sur Fedora

```bash
# Activer RPM Fusion si ffmpeg n'est pas disponible
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Installer les dépendances
sudo dnf install ffmpeg ImageMagick
```

> `yt-dlp` déjà installé ✅

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
ytdl-music <URL>
```

### Exemples

```bash
# YouTube
ytdl-music https://www.youtube.com/watch?v=xxxxx

# SoundCloud
ytdl-music https://soundcloud.com/artiste/titre

# Bandcamp, Vimeo, Twitter, et +1000 autres sites supportés par yt-dlp...
ytdl-music https://bandcamp.com/...
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

✔ Fichier créé : ~/Music/Queen - Bohemian Rhapsody.mp3
```

---

## Fichiers de sortie

Les MP3 sont sauvegardés dans **`~/Music/`** avec le format :

```
Artiste - Titre.mp3
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