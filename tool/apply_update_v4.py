#!/usr/bin/env python3
"""Anime Organizer V4 – safe patch, anchored to versions V2/V3."""
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]

def change(path, name, fn):
    file = root / path
    if not file.exists():
        raise RuntimeError(f'{path}: introuvable. Installer V3 et placer le ZIP dans le depot local.')
    original = file.read_text(encoding='utf-8')
    new = fn(original)
    if new != original:
        file.write_text(new, encoding='utf-8')
        print('OK:', path, name)
    else:
        print('Deja applique:', path, name)

def replace_once(s, old, new, path):
    if new in s: return s
    n = s.count(old)
    if n != 1: raise RuntimeError(f'{path}: motif attendu 1 fois, trouve {n}: {old[:65]!r}')
    return s.replace(old,new,1)

def model(s):
    p='lib/models/anime.dart'
    s=replace_once(s,'  String? imageUrl;\n  String? posterPath;', '  String? imageUrl;\n  String? backdropUrl;\n  String? posterPath;',p)
    s=replace_once(s,'    this.imageUrl,\n    this.posterPath,','    this.imageUrl,\n    this.backdropUrl,\n    this.posterPath,',p)
    s=replace_once(s,"        'imageUrl': imageUrl,\n        'posterPath': posterPath,", "        'imageUrl': imageUrl,\n        'backdropUrl': backdropUrl,\n        'posterPath': posterPath,",p)
    s=replace_once(s,"        imageUrl: j['imageUrl'] as String?,\n        posterPath: j['posterPath'] as String?,", "        imageUrl: j['imageUrl'] as String?,\n        backdropUrl: j['backdropUrl'] as String?,\n        posterPath: j['posterPath'] as String?,",p)
    return s

def controller(s):
    return replace_once(s,'    anime.imageUrl = meta.imageUrl;\n    anime.posterPath = null;', '    anime.imageUrl = meta.imageUrl;\n    anime.backdropUrl = null; // Jamais reutiliser une image de l\'ancienne identification.\n    anime.posterPath = null;', 'lib/services/library_controller.dart')

def detail(s):
    p='lib/screens/detail_screen.dart'
    s=replace_once(s,"import 'dart:io';", "import 'dart:io';\nimport 'dart:async';",p)
    s=replace_once(s,"import '../services/library_controller.dart';", "import '../services/library_controller.dart';\nimport '../services/backdrop_service.dart';",p)
    s=replace_once(s,'  Anime get anime => widget.anime;', '''  Anime get anime => widget.anime;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBackdrop());
  }

  Future<void> _loadBackdrop() async {
    if (anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty) return;
    final apiKey = library.settings.tmdbKey.trim();
    if (apiKey.isEmpty) return; // Pas de cle: l'affiche existante reste visible.
    final title = anime.apiTitle ?? anime.folderTitle;
    final url = await BackdropService.findBackdrop(title, apiKey);
    if (!mounted || url == null || url.isEmpty) return;
    anime.backdropUrl = url;
    await library.save();
    if (mounted) setState(() {});
  }''',p)
    # Background prefers widescreen and falls back to local poster.
    needle='''    final path = anime.posterPath;
    final remote = anime.imageUrl;
    Widget image;'''
    repl='''    final path = anime.backdropUrl == null ? anime.posterPath : null;
    final remote = anime.backdropUrl ?? anime.imageUrl;
    Widget image;'''
    s=replace_once(s,needle,repl,p)
    return s

def workflow(s):
    if '\n  release:\n' in s: return s
    if '\n  windows:\n' not in s or 'AnimeOrganizer-Android' not in s:
        raise RuntimeError('Workflow non reconnu, aucune modification appliquee.')
    # Expose content write only to release job; other jobs keep their existing perms.
    s += '''

  release:
    name: Publier les telechargements
    runs-on: ubuntu-latest
    needs: [android, windows]
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: AnimeOrganizer-Android
          path: dist/android
      - uses: actions/download-artifact@v4
        with:
          name: AnimeOrganizer-Installateur-Windows
          path: dist/windows-installer
      - uses: actions/download-artifact@v4
        with:
          name: AnimeOrganizer-Portable-Windows
          path: dist/windows-portable
      - name: Preparer les fichiers publics
        shell: bash
        run: |
          set -euo pipefail
          mkdir -p release
          cp dist/android/AnimeOrganizer.apk release/AnimeOrganizer.apk
          find dist/windows-installer -type f -name '*.exe' -print -quit | xargs -r -I {} cp '{}' release/AnimeOrganizer-Setup.exe
          cp dist/windows-portable/AnimeOrganizer-Windows-portable.zip release/AnimeOrganizer-Windows-portable.zip
          test -s release/AnimeOrganizer.apk
          test -s release/AnimeOrganizer-Setup.exe
          test -s release/AnimeOrganizer-Windows-portable.zip
      - name: Publier dans GitHub Releases
        shell: bash
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          TAG="v1.${{ github.run_number }}.0"
          gh release create "$TAG" release/* \\
            --repo "${{ github.repository }}" \\
            --target "${{ github.sha }}" \\
            --title "Anime Organizer $TAG" \\
            --notes "Application gratuite pour Android et Windows. Trois telechargements : APK, installateur Windows et version portable." \\
            --latest
'''
    return s

change('lib/models/anime.dart','backdrop',model)
change('lib/services/library_controller.dart','invalidation ancienne image',controller)
change('lib/screens/detail_screen.dart','image panoramique',detail)
change('.github/workflows/build.yml','releases',workflow)
print('Correctif V4 pret. Les fichiers sont modifies localement, aucun fichier video touche.')
