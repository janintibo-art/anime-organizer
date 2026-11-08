#!/usr/bin/env python3
"""Anime Organizer V10: ajout de dossiers non bloquant, patch idempotent.
Ne modifie aucune donnee de la bibliotheque, aucune video.
"""
from pathlib import Path

base = Path(__file__).resolve().parents[1]
home = base / 'lib/screens/home_screen.dart'
picker = base / 'lib/screens/folder_picker_screen.dart'
controller = base / 'lib/services/library_controller.dart'


def replace_once(text, old, new, path):
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: motif absent ou ambigu ({count}): {old[:100]!r}')
    return text.replace(old, new, 1)


def make_home(src):
    old_add = '''  Future<void> _addFolder() async {
    await _ensurePermissions();
    if (!mounted) return;
    final dir = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
    );
    if (dir == null) return;
    await library.addFolder(dir);
    await library.scan();
  }
'''
    new_add = '''  Future<void> _addFolder() async {
    try {
      await _ensurePermissions();
      if (!mounted) return;
      final dir = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
      );
      if (dir == null || dir.trim().isEmpty) return;
      if (!Directory(dir).existsSync()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dossier introuvable ou inaccessible.')));
        return;
      }
      final alreadyAdded = library.folders.contains(dir);
      await library.addFolder(dir);
      // Si un scan est en cours, le controleur met le nouveau scan en file.
      await library.scan();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        alreadyAdded ? 'Dossier deja present. Analyse demandee.'
            : 'Dossier ajoute. Analyse lancee ou programmee.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ajouter ce dossier : $e')));
    }
  }
'''
    src = replace_once(src,old_add,new_add,'home.addFolder')
    target = '''            actions: [
              IconButton(
                tooltip: 'Verifier les fiches incoherentes','''
    replacement = '''            actions: [
              IconButton(
                tooltip: 'Ajouter un dossier',
                onPressed: _addFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              IconButton(
                tooltip: 'Verifier les fiches incoherentes','''
    src=replace_once(src,target,replacement,'home.appBar')
    src=replace_once(src,'onPressed: library.busy ? null : _addFolder,','onPressed: _addFolder,','home.fab')
    return src


def make_picker(src):
    old = '''    if (widget.pickExtension == null) _preview(path);
'''
    new = '''    // Ne pas scanner recursivement pendant la navigation : sur une grosse
    // bibliotheque, cela bloquait la selection pendant des minutes.
    // L'analyse complete se fait APRES l'import, dans LibraryController.
'''
    src = replace_once(src,old,new,'picker.navigation')
    # La previsualisation ne doit plus empecher l'import ni faire croire que
    # le dossier est vide, meme s'il contient des videos dans des sous-dossiers.
    old_label = '''                child: _previewing
                    ? Text('Analyse en cours…',
                        style: TextStyle(color: Palette.muted, fontSize: 12))
                    : Text(
                        _previewVideos == 0
                            ? 'Aucune vidéo détectée ici'
                            : '$_previewSeries séries · $_previewVideos vidéos détectées',
                        style: TextStyle(
                          color: _previewVideos == 0
                              ? Palette.muted
                              : Palette.kin,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),'''
    new_label = '''                child: Text(
                  'Les videos seront analysees apres import.',
                  style: TextStyle(color: Palette.muted, fontSize: 12),
                ),'''
    src=replace_once(src,old_label,new_label,'picker.previewLabel')
    return src


def make_controller(src):
    marker='''  bool busy = false;
  String status = '';
'''
    src=replace_once(src,marker,'''  bool busy = false;
  bool _scanQueued = false;
  String status = '';
''','controller.state')
    start='''  Future<void> scan({bool fetchMetadata = true}) async {
    if (busy || folders.isEmpty) return;
    busy = true;
'''
    changed='''  Future<void> scan({bool fetchMetadata = true}) async {
    if (folders.isEmpty) return;
    if (busy) {
      _scanQueued = true;
      return;
    }
    busy = true;
'''
    src=replace_once(src,start,changed,'controller.scan')
    end='''    } finally {
      busy = false;
      _report('');
    }
  }

  /// Scan lance a l'ouverture de l'application'''
    new_end='''    } finally {
      busy = false;
      _report('');
      if (_scanQueued) {
        _scanQueued = false;
        // Lance une analyse supplementaire apres la fin de la precedente.
        // Les dossiers nouvellement ajoutes ne seront donc pas oublies.
        Future<void>.microtask(() async { await scan(); });
      }
    }
  }

  /// Scan lance a l'ouverture de l'application'''
    src=replace_once(src,end,new_end,'controller.queue')
    return src

changes=[]
for path,func in ((home,make_home),(picker,make_picker),(controller,make_controller)):
    original=path.read_text(encoding='utf8')
    updated=func(original)
    changes.append((path,original,updated))

# Toutes les verifications sont terminees avant la premiere ecriture.
for path,old,new in changes:
    if new!=old:
        path.write_text(new,encoding='utf8')
        print('Modifie :',path.relative_to(base))
    else:
        print('Deja a jour :',path.relative_to(base))
print('V10 appliquee. Les donnees utilisateur et fichiers videos sont conserves.')
