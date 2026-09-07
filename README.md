# Anime Organizer

Organise une collection d'animes stockee sur disque : scan des dossiers, recuperation
automatique des affiches, synopsis et genres via l'API Jikan (MyAnimeList), traduction
des descriptions anglaises, tri par genre ou alphabetique, et lecteur video integre.

Un seul code source Flutter produit l'application Windows (`.exe`) et Android (`.apk`).
La compilation est faite par GitHub Actions : aucun outil a installer sur ton PC.

## Ce que fait l'application

- Choix d'un ou plusieurs dossiers a surveiller ; chaque sous-dossier devient une serie
- Nettoyage automatique des noms de fichiers (`[Team] Titre.S01E03.1080p.mkv` devient `Titre`)
- Affiche, note, annee, genres et synopsis recuperes automatiquement
- Traduction des synopsis : MyMemory (gratuit, sans cle), LibreTranslate ou DeepL
- Tri A-Z, par genre, par note, par annee ou par nombre d'episodes ; recherche et favoris
- Lecture des videos dans l'application (mkv, mp4, avi, etc.) avec passage a l'episode suivant

## Compiler via GitHub

1. Pousse ce dossier dans un depot GitHub (voir les commandes Termux plus bas).
2. Onglet **Actions** du depot : le workflow « Compiler APK et EXE » demarre tout seul.
3. Au bout de 10 a 20 minutes, telecharge les artefacts en bas de la page du run :
   - `AnimeOrganizer-Android` contient l'APK a installer sur le telephone
   - `AnimeOrganizer-Windows` contient un zip a decompresser ; lance `anime_organizer.exe`

Le jeton GitHub utilise pour pousser doit avoir les droits **repo** et **workflow**,
sinon GitHub refuse le fichier `.github/workflows/build.yml`.

## Commandes Termux

```bash
pkg update -y && pkg upgrade -y
pkg install -y git unzip curl
termux-setup-storage
cd ~ && unzip -o /sdcard/Download/anime_organizer.zip -d ~/
cd ~/anime_organizer
git config --global user.name "TON_PSEUDO"
git config --global user.email "ton@email.com"
git init -b main
git add .
git commit -m "Premiere version"
export GH_USER="TON_PSEUDO"
export GH_TOKEN="ghp_ton_jeton"
curl -s -u "$GH_USER:$GH_TOKEN" https://api.github.com/user/repos -d '{"name":"anime-organizer","private":false}'
git remote add origin "https://$GH_USER:$GH_TOKEN@github.com/$GH_USER/anime-organizer.git"
git push -u origin main
```

Pour envoyer une modification par la suite :

```bash
cd ~/anime_organizer && git add . && git commit -m "mise a jour" && git push
```

## Installer l'APK

L'APK n'est pas signe par le Play Store : autorise l'installation depuis des sources
inconnues. Au premier lancement, l'application demande l'acces au stockage. Sur
Android 11 et plus, accorde « Acces a tous les fichiers », sinon le scan ne verra rien.

Si le selecteur de dossiers ne renvoie pas un chemin exploitable, utilise
« Saisir un chemin a la main » et donne par exemple `/storage/emulated/0/Animes`.

## Confidentialite

Les videos ne quittent jamais l'appareil. Seuls les titres de series sont envoyes
a l'API de metadonnees et au service de traduction.

## Limites connues

- Jikan limite a 3 requetes par seconde : un premier scan de 200 series prend quelques minutes.
- MyMemory sans email est limite a 5 000 caracteres par jour. Renseigne un email dans
  les reglages pour passer a 50 000, ou utilise DeepL.
- Le zip Windows contient l'exe et ses DLL : garde le dossier entier.
