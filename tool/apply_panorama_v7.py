#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'lib/screens/detail_screen.dart'
if not p.exists(): raise SystemExit('ERREUR : projet Flutter introuvable (lib/screens/detail_screen.dart).')
s=p.read_text(encoding='utf-8')
if 'Actualiser le panorama' in s:
    print('V7 deja appliquee.'); raise SystemExit(0)
if 'BackdropService.findBackdrop' not in s or 'backdropUrl' not in s:
    raise SystemExit('ERREUR : la V4 (panoramas) doit etre installee avant la V7. Aucune modification.')
old='''  Future<void> _loadBackdrop() async {
    if (anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty) return;
    final apiKey = library.settings.tmdbKey.trim();
    if (apiKey.isEmpty) return; // Pas de cle: l'affiche existante reste visible.
    final title = anime.apiTitle ?? anime.folderTitle;
    final url = await BackdropService.findBackdrop(title, apiKey);
    if (!mounted || url == null || url.isEmpty) return;
    anime.backdropUrl = url;
    await library.save();
    if (mounted) setState(() {});
  }'''
new='''  Future<void> _loadBackdrop({bool force = false}) async {
    if (!force && anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty) return;
    final apiKey = library.settings.tmdbKey.trim();
    if (apiKey.isEmpty) {
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Renseigne ta clé TMDB dans les réglages pour chercher un panorama.'),
        ));
      }
      return;
    }
    if (force && mounted) setState(() => _working = true);
    try {
      final titles = <String>{
        if (anime.apiTitle != null) anime.apiTitle!,
        if (anime.romajiTitle != null) anime.romajiTitle!,
        anime.folderTitle,
      }.where((t) => t.trim().isNotEmpty);
      String? url;
      for (final title in titles) {
        url = await BackdropService.findBackdrop(title, apiKey);
        if (url != null) break;
      }
      if (!mounted) return;
      if (url != null) {
        anime.backdropUrl = url;
        await library.save();
        if (mounted) setState(() {});
      }
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          url == null ? 'Aucun panorama fiable trouvé : affiche conservée.' : 'Panorama actualisé.'
        )));
      }
    } finally {
      if (force && mounted) setState(() => _working = false);
    }
  }'''
button='''                          OutlinedButton.icon(
                            onPressed: _working ? null : () => _loadBackdrop(force: true),
                            icon: const Icon(Icons.landscape_outlined, size: 18),
                            label: const Text('Actualiser le panorama'),
                          ),
'''
anchor='''                          PopupMenuButton<String>(
                            tooltip: 'Catégorie','''
if s.count(old)!=1 or s.count(anchor)!=1: raise SystemExit(f'Motifs inattendus : fonction {s.count(old)} / bouton {s.count(anchor)}. Aucun fichier modifie.')
s=s.replace(old,new,1).replace(anchor,button+anchor,1)
p.write_text(s,encoding='utf-8')
print('V7 appliquee : bouton panorama, recherche multi-titres, conservation du fond si introuvable.')
