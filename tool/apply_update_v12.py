#!/usr/bin/env python3
"""V12: diagnostic des faux titres et reglage des panoramas (patch idempotent)."""
from pathlib import Path
import sys

root=Path(__file__).resolve().parent.parent

def edit(path,changes):
 p=root/path
 if not p.exists(): raise RuntimeError(f'Fichier absent : {path}')
 s=p.read_text(encoding='utf-8'); original=s
 for before,after in changes:
  if after in s:continue
  n=s.count(before)
  if n!=1:raise RuntimeError(f'{path}: repere ambigu ou absent ({n}) : {before[:90]!r}')
  s=s.replace(before,after,1)
 if s!=original:
  p.write_text(s,encoding='utf-8');print('Modifie :',path)
 else:print('Deja a jour :',path)

edit('lib/services/scanner.dart', [
 ('for (final e in episodes.take(12)) {','for (final e in episodes.take(80)) {'),
 ('''    // Un fichier unique explicite suffit ; sinon confirmation par deux vidéos.
    if (episodes.length > 1 && sorted.first.value < 2) return null;
    return sorted.first.key;''','''    // Un consensus clair est obligatoire pour ne pas nommer une saison
    // entiere d'apres une video isolee ou un titre parasite.
    if (episodes.length > 1 && sorted.first.value < 2) return null;
    if (names.length >= 4 && sorted.first.value / names.length < 0.65) return null;
    return sorted.first.key;''')
])

# On ne touche pas aux metadata protegees par une correction manuelle.
# L'inspection ne declenche aucune recherche API lorsque le nom de fichier est ambigu.
edit('lib/services/library_controller.dart', [
 ('''  /// Re-examine les fiches deja identifiees en comparant le titre avec''','''  /// Remet en coherence les fiches trompeuses, meme si les serveurs sont
  /// momentanement injoignables. Le resultat est conservateur : seul un
  /// titre present dans plusieurs fichiers peut invalider des metadonnees.
  int lastScanSuspects = 0;
  int lastScanUnresolved = 0;

  void _clearWrongMetadata(Anime anime, String detectedTitle) {
    final oldTitle = anime.folderTitle;
    anime.folderTitle = detectedTitle;
    anime.apiTitle = null;
    anime.nativeTitle = null;
    anime.romajiTitle = null;
    anime.frenchTitle = null;
    anime.malId = null;
    anime.imageUrl = null;
    anime.backdropUrl = null;
    anime.backdropManual = false;
    anime.posterPath = null;
    anime.synopsisEn = null;
    anime.synopsisTranslated = null;
    anime.genres = [];
    anime.score = null;
    anime.popularity = null;
    anime.studios = null;
    anime.metaSource = null;
    anime.year = null;
    anime.type = null;
    anime.status = null;
    anime.episodesCount = null;
    anime.metaFetched = false;
    anime.metaFailed = false;
    anime.metaFailCount = 0;
    // Une ancienne association fautive ne doit plus etre reutilisee.
    knownTitles.remove(_key(oldTitle));
    knownTitles.remove(_key(detectedTitle));
  }

  /// Re-examine les fiches deja identifiees en comparant le titre avec'''),
 ('''    var repaired = 0;
    try {
      final suspicious = animes.where((a) {''','''    var repaired = 0;
    lastScanSuspects = 0;
    lastScanUnresolved = 0;
    try {
      final suspicious = animes.where((a) {'''),
 ('''      for (var i = 0; i < suspicious.length; i++) {
        final anime = suspicious[i];''','''      lastScanSuspects = suspicious.length;
      for (var i = 0; i < suspicious.length; i++) {
        final anime = suspicious[i];'''),
 ('''        if (match == null ||
            MetadataService.similarity(file, match.title) < 0.72) continue;
        applyMeta(anime, match);''','''        // Une fiche DBZ ne doit pas rester affichee comme vraie simplement
        // parce qu'aucune API n'a repondu. Afficher le titre du fichier.
        // Les corrections manuelles restent exclues du scan.
        if (match == null ||
            MetadataService.similarity(file, match.title) < 0.72) {
          _clearWrongMetadata(anime, file);
          lastScanUnresolved++;
          repaired++;
          await save();
          notifyListeners();
          continue;
        }
        applyMeta(anime, match);'''),
])

edit('lib/models/anime.dart', [
 ('''  bool backdropManual = false;''','''  bool backdropManual = false;
  double backdropAlignX = 0.0;
  double backdropAlignY = 0.0;'''),
 ('''    this.backdropManual = false,''','''    this.backdropManual = false,
    this.backdropAlignX = 0.0,
    this.backdropAlignY = 0.0,'''),
 ('''        'backdropManual': backdropManual,''','''        'backdropManual': backdropManual,
        'backdropAlignX': backdropAlignX,
        'backdropAlignY': backdropAlignY,'''),
 ('''        backdropManual: j['backdropManual'] as bool? ?? false,''','''        backdropManual: j['backdropManual'] as bool? ?? false,
        backdropAlignX: (j['backdropAlignX'] as num?)?.toDouble() ?? 0.0,
        backdropAlignY: (j['backdropAlignY'] as num?)?.toDouble() ?? 0.0,'''),
])

edit('lib/screens/detail_screen.dart', [
 ('''  Widget _backgroundArt() {''','''  Future<void> _adjustBackdrop() async {
    var x = anime.backdropAlignX;
    var y = anime.backdropAlignY;
    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Cadrage du panorama'),
        content: SizedBox(width: 390, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (anime.backdropUrl != null)
              AspectRatio(aspectRatio: 16/9,
                child: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: anime.backdropUrl!, fit: BoxFit.cover,
                    alignment: Alignment(x, y),
                  ))),
            const SizedBox(height: 12),
            const Text('Deplacer horizontalement'),
            Slider(value: x, min: -1, max: 1,
              onChanged: (v) => refresh(() => x = v)),
            const Text('Deplacer verticalement'),
            Slider(value: y, min: -1, max: 1,
              onChanged: (v) => refresh(() => y = v)),
          ],
        )),
        actions: [
          TextButton(onPressed: () => refresh(() {x=0; y=0;}),
            child: const Text('Centrer')),
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer')),
        ],
      )),
    );
    if (changed != true || !mounted) return;
    anime.backdropAlignX = x;
    anime.backdropAlignY = y;
    await library.save();
    if (mounted) setState(() {});
  }

  Widget _backgroundArt() {'''),
 ('''    final remote = anime.backdropUrl ?? anime.imageUrl;
    Widget image;''','''    final remote = anime.backdropUrl ?? anime.imageUrl;
    final position = Alignment(anime.backdropAlignX, anime.backdropAlignY);
    Widget image;'''),
 ('''image = Image.file(File(path), fit: BoxFit.cover,
          alignment: Alignment.topCenter,''','''image = Image.file(File(path), fit: BoxFit.cover,
          alignment: position,'''),
 ('''image = CachedNetworkImage(imageUrl: remote, fit: BoxFit.cover,
          alignment: Alignment.topCenter,''','''image = CachedNetworkImage(imageUrl: remote, fit: BoxFit.cover,
          alignment: position,'''),
 ('''                alignment: Alignment.center,
                errorWidget:''','''                alignment: Alignment(anime.backdropAlignX, anime.backdropAlignY),
                errorWidget:'''),
 ('''                            label: const Text('Choisir le panorama'),''','''                            label: const Text('Choisir le panorama'),'''),
])
# Ajouter le bouton avec repere moins fragile, apres la fonction de choix.
p=root/'lib/screens/detail_screen.dart';s=p.read_text(encoding='utf-8')
marker="label: const Text('Actualiser le panorama'),"
if "label: const Text('Ajuster le cadrage')" not in s:
 i=s.find(marker)
 if i<0: raise RuntimeError('Bouton panorama introuvable')
 j=s.find('                          ),',i)
 if j<0:raise RuntimeError('Fin bouton introuvable')
 j+=len('                          ),')
 s=s[:j]+'''
                          OutlinedButton.icon(
                            onPressed: anime.backdropUrl == null ? null : _adjustBackdrop,
                            icon: const Icon(Icons.crop_free, size: 18),
                            label: const Text('Ajuster le cadrage'),
                          ),'''+s[j:]
 p.write_text(s,encoding='utf-8')
 print('Ajoute bouton de cadrage')
print('V12 appliquee : scanner, coherence des fiches, cadrage panoramas')
