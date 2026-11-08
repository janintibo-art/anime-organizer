from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
model=ROOT/'lib/models/anime.dart'
detail=ROOT/'lib/screens/detail_screen.dart'
pub=ROOT/'pubspec.yaml'
files={p:p.read_text(encoding='utf-8') for p in (model,detail,pub)}
def change(p,old,new):
    s=files[p]; n=s.count(old)
    if n!=1:raise RuntimeError(f'{p.relative_to(ROOT)}: attendu 1 ancrage, trouvé {n}: {old[:70]!r}')
    files[p]=s.replace(old,new,1)
# file picker available on Windows/Android. No unsupported native UI for importing.
change(pub,'  path_provider: ^2.1.4\n','  path_provider: ^2.1.4\n  file_picker: ^8.3.7\n')
change(model,'  String? backdropUrl;\n','  String? backdropUrl;\n  String? backdropLocalPath; // V25: image personnelle copiee dans le stockage de l’application.\n')
change(model,'    this.backdropUrl,\n','    this.backdropUrl,\n    this.backdropLocalPath,\n')
change(model,"        'backdropUrl': backdropUrl,\n","        'backdropUrl': backdropUrl,\n        'backdropLocalPath': backdropLocalPath,\n")
change(model,"        backdropUrl: j['backdropUrl'] as String?,\n","        backdropUrl: j['backdropUrl'] as String?,\n        backdropLocalPath: j['backdropLocalPath'] as String?,\n")
change(detail,"import 'dart:async';\n","import 'dart:async';\nimport 'dart:ui' as ui;\n\nimport 'package:file_picker/file_picker.dart';\nimport 'package:path/path.dart' as p;\nimport 'package:path_provider/path_provider.dart';\n")
change(detail,'    if (anime.backdropManual) return;','    if (anime.backdropManual || anime.backdropLocalPath != null) return;')
change(detail,'    if (selection.isEmpty) {\n      anime.backdropManual = false;','    if (selection.isEmpty) {\n      anime.backdropLocalPath = null;\n      anime.backdropManual = false;')
change(detail,'    } else {\n      anime.backdropManual = true;\n      anime.backdropUrl = selection;','    } else {\n      anime.backdropLocalPath = null;\n      anime.backdropManual = true;\n      anime.backdropUrl = selection;')
change(detail,'            if (anime.backdropUrl != null)\n              AspectRatio(', '            if (anime.backdropLocalPath != null && File(anime.backdropLocalPath!).existsSync())\n              AspectRatio(aspectRatio: 16/9,\n                child: ClipRRect(borderRadius: BorderRadius.circular(8),\n                  child: Image.file(File(anime.backdropLocalPath!), fit: BoxFit.cover,\n                    alignment: Alignment(x, y))))\n            else if (anime.backdropUrl != null)\n              AspectRatio(')
old='''  Widget _backgroundArt() {
    final path = anime.backdropUrl == null ? anime.posterPath : null;
    final remote = anime.backdropUrl ?? anime.imageUrl;
    final position = Alignment(anime.backdropAlignX, anime.backdropAlignY);
    Widget image;
    if (path != null && File(path).existsSync()) {
      image = Image.file(File(path), fit: BoxFit.cover,
          alignment: position,
          errorBuilder: (_, __, ___) => const SizedBox.shrink());
    } else if (remote != null && remote.isNotEmpty) {
      image = CachedNetworkImage(imageUrl: remote, fit: BoxFit.cover,
          alignment: position,
          errorWidget: (_, __, ___) => const SizedBox.shrink());
    } else {
      image = const SizedBox.shrink();
    }
'''
new='''  Widget _backgroundArt() {
    final position = Alignment(anime.backdropAlignX, anime.backdropAlignY);
    final local = anime.backdropLocalPath;
    Widget image;
    if (local != null && File(local).existsSync()) {
      image = Image.file(File(local), fit: BoxFit.cover,
          alignment: position, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    } else if (anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty) {
      image = CachedNetworkImage(imageUrl: anime.backdropUrl!, fit: BoxFit.cover,
          alignment: position, errorWidget: (_, __, ___) => const SizedBox.shrink());
    } else {
      // V25: aucune affiche verticale agrandie en faux panorama.
      image = const DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF192734), Color(0xFF10151D), Color(0xFF30202B)])));
    }
'''
change(detail,old,new)
newmethods='''  // V25_PANORAMA_LOCAL: copie perenne et validation des dimensions.
  Future<void> _importLocalBackdrop() async {
    if (_working) return;
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: false);
      if (selection == null || selection.files.isEmpty) return;
      final sourcePath = selection.files.single.path;
      if (sourcePath == null || sourcePath.isEmpty) throw const FormatException('Fichier inaccessible.');
      final source = File(sourcePath);
      if (!await source.exists()) throw const FormatException('Fichier introuvable.');
      if (await source.length() > 25 * 1024 * 1024) {
        throw const FormatException('Image trop volumineuse (maximum 25 Mo).');
      }
      final bytes = await source.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (width < 960 || height < 540 || width / height < 1.3) {
        throw const FormatException('Choisis une image paysage de 960 × 540 minimum.');
      }
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'panoramas'));
      await dir.create(recursive: true);
      final extension = p.extension(source.path).toLowerCase();
      final name = 'panorama_${DateTime.now().microsecondsSinceEpoch}${extension}';
      final destination = File(p.join(dir.path, name));
      await destination.writeAsBytes(bytes, flush: true);
      final previous = anime.backdropLocalPath;
      anime.backdropLocalPath = destination.path;
      anime.backdropManual = true;
      anime.backdropAlignX = 0;
      anime.backdropAlignY = 0;
      await library.save();
      library.refresh();
      if (mounted) setState(() {});
      // Supprimer seulement une ancienne copie gérée par l’application.
      if (previous != null && p.isWithin(dir.path, previous)) {
        try { await File(previous).delete(); } catch (_) {}
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Panorama personnel enregistré.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import impossible : $e')));
    }
  }

  Future<void> _removeLocalBackdrop() async {
    final previous = anime.backdropLocalPath;
    anime.backdropLocalPath = null;
    anime.backdropManual = false;
    anime.backdropUrl = null;
    await library.save();
    library.refresh();
    if (mounted) setState(() {});
    if (previous != null) {
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'panoramas'));
      if (p.isWithin(dir.path, previous)) {
        try { await File(previous).delete(); } catch (_) {}
      }
    }
    unawaited(_loadBackdrop());
  }

'''
change(detail,'  Widget _backgroundArt() {',newmethods+'  Widget _backgroundArt() {')
change(detail,"      case 'choose': await _chooseBackdrop(); break;", "      case 'choose': await _chooseBackdrop(); break;\n      case 'import_local': await _importLocalBackdrop(); break;\n      case 'remove_local': await _removeLocalBackdrop(); break;")
change(detail,"            PopupMenuItem(value: 'crop', child: ListTile(","            PopupMenuItem(value: 'import_local', child: ListTile(\n              dense: true, leading: Icon(Icons.add_photo_alternate_outlined),\n              title: Text('Importer un panorama du disque'))),\n            PopupMenuItem(value: 'remove_local', child: ListTile(\n              dense: true, leading: Icon(Icons.restore),\n              title: Text('Revenir au panorama automatique'))),\n            PopupMenuItem(value: 'crop', child: ListTile(")
change(detail,"if (anime.backdropUrl != null) await _adjustBackdrop();", "if (anime.backdropUrl != null || anime.backdropLocalPath != null) await _adjustBackdrop();")
# reject user's local panorama being overwritten by stale metadata? keep local path separate.
for file,content in files.items():file.write_text(content,encoding='utf-8')
print('V25: patches valides et appliques :', ', '.join(str(x.relative_to(ROOT)) for x in files))
