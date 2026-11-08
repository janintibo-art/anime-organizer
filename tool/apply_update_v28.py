#!/usr/bin/env python3
"""Anime Organizer V28 - mise à jour ciblée, vérification des ancrages et sauvegardes."""
from pathlib import Path
import os
import shutil
import tempfile

ROOT=Path(__file__).resolve().parents[1]
changes={}

def load(rel):
    f=ROOT/rel
    if not f.is_file(): raise RuntimeError('Fichier introuvable : '+rel)
    return f.read_text(encoding='utf-8')

def once(src,old,new,label):
    count=src.count(old)
    if count!=1: raise RuntimeError(f'{label}: ancrage attendu une fois, trouvé {count}')
    return src.replace(old,new,1)

model='lib/models/anime.dart'
s=load(model)
if 'V28_GALLERY_ORDER' not in s:
    s=once(s,'  bool slideshowEnabled = false;','  // V28_GALLERY_ORDER : chemins de captures dans l’ordre choisi.\n  List<String> galleryOrder = [];\n  bool slideshowEnabled = false;', 'modèle - état')
    s=once(s,'    this.slideshowEnabled = false,','    List<String>? galleryOrder,\n    this.slideshowEnabled = false,','modèle - constructeur')
    s=once(s,'  })  : creditMarkers = creditMarkers ?? <String, Map<String, int>>{},','  })  : galleryOrder = galleryOrder ?? <String>[],\n        creditMarkers = creditMarkers ?? <String, Map<String, int>>{},','modèle - initialisation')
    s=once(s,"        'slideshowEnabled': slideshowEnabled,","        'galleryOrder': galleryOrder,\n        'slideshowEnabled': slideshowEnabled,",'modèle - json')
    s=once(s,"        slideshowEnabled: j['slideshowEnabled'] as bool? ?? false,","        galleryOrder: (j['galleryOrder'] as List? ?? const []).map((x) => x.toString()).toList(),\n        slideshowEnabled: j['slideshowEnabled'] as bool? ?? false,",'modèle - lecture json')
    changes[model]=s

path='lib/screens/detail_screen.dart'
s=load(path)
if 'V28_GALLERY_VISUELLE' not in s:
    s=once(s,"import 'dart:ui' as ui;", "import 'dart:ui' as ui;\n// V28_GALLERY_VISUELLE: aperçus, ordre, suppression et ouverture du dossier.", 'detail import')
    s=once(s,'    final files = await CaptureGallery.list(anime);', '''    final files = await CaptureGallery.list(anime);
    final priorities = anime.galleryOrder;
    files.sort((a, b) {
      final ia = priorities.indexOf(a);
      final ib = priorities.indexOf(b);
      if (ia < 0 && ib < 0) return a.compareTo(b);
      if (ia < 0) return 1;
      if (ib < 0) return -1;
      return ia.compareTo(ib);
    });''','tri galerie')
    a=s.index('  Future<void> _galleryOptions() async {')
    b=s.index('\n  Anime get anime => widget.anime;',a)
    new='''  Future<void> _galleryOptions() async {
    await _reloadGallery();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .86),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
            const Text('Galerie et diaporama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${_gallery.length} captures sauvegardées'),
            if (Platform.isWindows)
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                onPressed: () async {
                  try {
                    final dir = await CaptureGallery.folder(anime);
                    await Process.start('explorer.exe', [dir.path], mode: ProcessStartMode.detached);
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Impossible d’ouvrir le dossier : $e')));
                  }
                },
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Ouvrir le dossier des captures'))),
            SwitchListTile(
              title: const Text('Activer le diaporama'),
              value: anime.slideshowEnabled,
              onChanged: _gallery.length < 2 ? null : (v) async {
                anime.slideshowEnabled = v;
                await library.save();
                if (!ctx.mounted) return;
                redraw(() {});
                setState(() {});
                _startSlideshow();
              },
            ),
            ListTile(title: const Text('Durée par image'),
              subtitle: Text('${anime.slideshowSeconds} secondes')),
            Slider(value: anime.slideshowSeconds.toDouble(), min: 3, max: 30,
              divisions: 27,
              onChanged: (v) => redraw(() => anime.slideshowSeconds = v.round()),
              onChangeEnd: (v) async {
                await library.save();
                _startSlideshow();
              }),
            if (_gallery.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Choisir le panorama, déplacer ou supprimer une capture :')),
              LayoutBuilder(builder: (ctx, constraints) {
                final columns = constraints.maxWidth >= 650 ? 3 :
                    constraints.maxWidth >= 390 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _gallery.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns, crossAxisSpacing: 10,
                    mainAxisSpacing: 10, mainAxisExtent: 196),
                  itemBuilder: (ctx, index) {
                    final path = _gallery[index];
                    return Card(clipBehavior: Clip.antiAlias,
                      color: Palette.ink,
                      child: Column(children: [
                        Expanded(child: InkWell(
                          onTap: () async {
                            anime.backdropLocalPath = path;
                            anime.backdropManual = true;
                            await library.save();
                            if (mounted) setState(() {});
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: SizedBox(width: double.infinity,
                            child: Image.file(File(path), fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined))))),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          child: Text(p.basename(path), maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11))),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          IconButton(icon: const Icon(Icons.arrow_back, size: 18),
                            tooltip: 'Vers la gauche', onPressed: index == 0 ? null : () async {
                              final item = _gallery.removeAt(index);
                              _gallery.insert(index - 1, item);
                              anime.galleryOrder = List<String>.from(_gallery);
                              await library.save();
                              if (!ctx.mounted) return;
                              redraw(() {});
                              setState(() {});
                            }),
                          IconButton(icon: const Icon(Icons.arrow_forward, size: 18),
                            tooltip: 'Vers la droite', onPressed: index == _gallery.length - 1 ? null : () async {
                              final item = _gallery.removeAt(index);
                              _gallery.insert(index + 1, item);
                              anime.galleryOrder = List<String>.from(_gallery);
                              await library.save();
                              if (!ctx.mounted) return;
                              redraw(() {});
                              setState(() {});
                            }),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: 'Supprimer cette capture', onPressed: () async {
                              final ok = await showDialog<bool>(context: ctx,
                                builder: (dialogCtx) => AlertDialog(
                                  title: const Text('Supprimer cette capture ?'),
                                  content: Text(p.basename(path)), actions: [
                                    TextButton(onPressed: () => Navigator.pop(dialogCtx, false),
                                      child: const Text('Annuler')),
                                    FilledButton(onPressed: () => Navigator.pop(dialogCtx, true),
                                      child: const Text('Supprimer')),
                                  ]));
                              if (ok != true) return;
                              final directory = await CaptureGallery.folder(anime);
                              if (!p.isWithin(directory.path, path)) return;
                              try { await File(path).delete(); } catch (e) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Suppression impossible : $e')));
                                return;
                              }
                              if (anime.backdropLocalPath == path) {
                                anime.backdropLocalPath = null;
                                anime.backdropManual = false;
                              }
                              _gallery.remove(path);
                              anime.galleryOrder = List<String>.from(_gallery);
                              if (_gallery.length < 2) anime.slideshowEnabled = false;
                              _galleryIndex = 0;
                              await library.save();
                              _startSlideshow();
                              if (!ctx.mounted) return;
                              redraw(() {});
                              setState(() {});
                            }),
                        ]),
                      ]));
                  });
              }),
            ],
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer')),
          ]),
        ),
      )),
    );
  }
'''
    s=s[:a]+new+s[b:]
    s=once(s,'        image,\n        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(','''        AnimatedSwitcher(
          duration: const Duration(milliseconds: 950),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand,
            children: [...previous, if (current != null) current]),
          child: SizedBox.expand(key: ValueKey<String>(
            local ?? anime.backdropUrl ?? 'fallback'), child: image),
        ),
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(''','fondu panoramique')
    changes[path]=s

for rel,new in changes.items():
    old=ROOT/rel
    backup=old.with_suffix(old.suffix+'.v27-backup')
    if not backup.exists(): shutil.copy2(old,backup)
    fd,tn=tempfile.mkstemp(prefix='.v28-',dir=str(old.parent))
    with os.fdopen(fd,'w',encoding='utf-8') as o: o.write(new)
    os.replace(tn,old)
print('V28 : '+', '.join(changes.keys())+' mis à jour.')
