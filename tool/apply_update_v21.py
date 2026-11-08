#!/usr/bin/env python3
"""Anime Organizer V21: fiche immersive + menu d'actions. Repeat-safe."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / 'lib/screens/detail_screen.dart'
if not P.is_file():
    raise SystemExit('Projet introuvable : lib/screens/detail_screen.dart')
s = P.read_text(encoding='utf-8')
if 'V21_MENU_IMMERSIF' in s:
    print('V21 deja appliquee : aucune modification.'); raise SystemExit(0)

def exactly(old, new, what):
    global s
    n = s.count(old)
    if n != 1:
        raise RuntimeError(f'{what}: attendu 1 emplacement, trouve {n}. Aucun fichier modifie.')
    s = s.replace(old, new, 1)

# First remove long action strip from the main page; avoid modifying any of its methods.
start = '''                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _working ? null : _translate,'''
end = '''                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,'''
if s.count(start) != 1 or s.count(end) != 1:
    raise RuntimeError('Bande de commandes non reconnue : projet modifie ou V20 manquante.')
a=s.index(start); b=s.index(end,a)
if b-a>7000 or b<a: raise RuntimeError('Emplacements incoherents, arret.')
s=s[:a]+'''                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,'''+s[b+len(end):]
exactly('''                      _healthCard(),
''', '', 'Masquer panneau Etat de la collection')

# Menu actions is attached to top app bar; Favorite remains visible.
needle = '''      actions: [
        IconButton(
          tooltip: 'Favori','''
replacement='''      actions: [
        // V21_MENU_IMMERSIF: les reglages occasionnels quittent le panorama.
        PopupMenuButton<String>(
          tooltip: 'Informations et options de la fiche',
          icon: const Icon(Icons.more_vert),
          onSelected: _detailMenuAction,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'health', child: ListTile(
              dense: true, leading: Icon(Icons.fact_check_outlined),
              title: Text('Etat de la collection'))),
            PopupMenuItem(value: 'titles', child: ListTile(
              dense: true, leading: Icon(Icons.translate_outlined),
              title: Text('Titres et langues'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'translate', child: ListTile(
              dense: true, leading: Icon(Icons.translate),
              title: Text('Traduire la description'))),
            PopupMenuItem(value: 'original', child: ListTile(
              dense: true, leading: Icon(Icons.menu_book_outlined),
              title: Text('Voir original / traduction'))),
            PopupMenuItem(value: 'background', child: ListTile(
              dense: true, leading: Icon(Icons.wallpaper_outlined),
              title: Text('Changer le mode de fond'))),
            PopupMenuItem(value: 'refresh', child: ListTile(
              dense: true, leading: Icon(Icons.landscape_outlined),
              title: Text('Actualiser le panorama'))),
            PopupMenuItem(value: 'choose', child: ListTile(
              dense: true, leading: Icon(Icons.collections_outlined),
              title: Text('Choisir le panorama'))),
            PopupMenuItem(value: 'crop', child: ListTile(
              dense: true, leading: Icon(Icons.crop_free),
              title: Text('Ajuster le cadrage'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'category', child: ListTile(
              dense: true, leading: Icon(Icons.category_outlined),
              title: Text('Changer la categorie'))),
            PopupMenuItem(value: 'correct', child: ListTile(
              dense: true, leading: Icon(Icons.search),
              title: Text('Corriger la fiche'))),
            PopupMenuItem(value: 'ai', child: ListTile(
              dense: true, leading: Icon(Icons.auto_awesome),
              title: Text('Identifier avec l IA'))),
          ],
        ),
        IconButton(
          tooltip: 'Favori','''
exactly(needle,replacement,'Bouton menu')

methods='''  Future<void> _detailMenuAction(String action) async {
    if (_working && !['health', 'titles', 'original', 'background'].contains(action)) {
      return;
    }
    switch (action) {
      case 'health':
        final issues = anime.issues;
        final twins = library.duplicatesOf(anime);
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          backgroundColor: Palette.surface,
          title: const Text('Etat de la collection'),
          content: SizedBox(
            width: 570,
            child: SingleChildScrollView(child:
              issues.isEmpty && twins.isEmpty
                ? const Text('Aucune anomalie detectee dans cette collection.')
                : _healthCard()),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'))],
        ));
        break;
      case 'titles':
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          backgroundColor: Palette.surface,
          title: const Text('Titres et langues'),
          content: SingleChildScrollView(child: SizedBox(
            width: 540, child: _titleVariants())),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'))],
        ));
        break;
      case 'translate': await _translate(); break;
      case 'original': setState(() => _showOriginal = !_showOriginal); break;
      case 'background':
        setState(() => _immersiveBackground = !_immersiveBackground); break;
      case 'refresh': await _loadBackdrop(force: true); break;
      case 'choose': await _chooseBackdrop(); break;
      case 'crop':
        if (anime.backdropUrl != null) await _adjustBackdrop();
        break;
      case 'correct': await _searchAgain(); break;
      case 'ai': await _askAi(); break;
      case 'category':
        if (!mounted) return;
        final chosen = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Palette.surface,
          builder: (ctx) => SafeArea(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              ListTile(title: const Text('Anime japonais'),
                onTap: () => Navigator.pop(ctx, 'anime')),
              ListTile(title: const Text('Dessin anime'),
                onTap: () => Navigator.pop(ctx, 'western')),
              ListTile(title: const Text('Animation adulte'),
                onTap: () => Navigator.pop(ctx, 'adult')),
              ListTile(title: const Text('Autre animation'),
                onTap: () => Navigator.pop(ctx, 'other')),
            ],
          )),
        );
        if (chosen != null) {
          anime.category = chosen;
          await library.save();
          library.refresh();
        }
        break;
    }
  }

'''
exactly('''  // ---------------------------------------------------------------- bandeau
''', methods+'''  // ---------------------------------------------------------------- bandeau
''', 'Methode actions menu')
# Keep the collapsible 'titles and languages' link for accessibility; menu adds a second entry.
backup=P.with_suffix('.dart.v20-backup')
if not backup.exists(): shutil.copy2(P,backup)
P.write_text(s,encoding='utf-8')
print('V21 appliquee avec succes : menu en haut a droite, diagnostic et commandes deplaces.')
