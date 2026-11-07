#!/usr/bin/env python3
"""Apply V19 safely, all anchors verified before writing."""
from pathlib import Path
import re, sys

BASE=Path(__file__).resolve().parents[1]
player=BASE/'lib/screens/player_screen.dart'
workflow=BASE/'.github/workflows/build.yml'
if not player.exists() or not workflow.exists():
    raise SystemExit('Projet Flutter non trouvé : vérifier le dossier du dépôt.')
s=player.read_text(encoding='utf-8')
w=workflow.read_text(encoding='utf-8')
if 'V19_CREDITS_DETECTOR' in s:
    print('V19 déjà appliquée : aucun changement.');sys.exit(0)

def replace_one(txt,old,new,path):
    count=txt.count(old)
    if count!=1:raise RuntimeError(f'{path} : ancre trouvée {count} fois au lieu de 1')
    return txt.replace(old,new,1)

s=replace_one(s,"import 'dart:async';", "import 'dart:async';\nimport 'dart:convert';",str(player))
s=replace_one(s,"import 'package:flutter/services.dart';", "import 'package:flutter/services.dart';\nimport 'package:path/path.dart' as p;\nimport 'package:path_provider/path_provider.dart';",str(player))

method=r'''
  // V19_CREDITS_DETECTOR: détection prudente, validation explicite.
  Future<void> _detectCreditsAutomatically() async {
    if (!Platform.isWindows || widget.anime == null || widget.episodes.isEmpty) {
      _flash('La détection automatique est disponible sur Windows.');
      return;
    }
    final current = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    final season = current.season ?? 1;
    final samples = widget.episodes.where((e) =>
      !e.bonus && (e.season ?? 1) == season && File(e.path).existsSync())
        .take(4).map((e) => e.path).toList();
    if (samples.length < 3) {
      _flash('Il faut au moins 3 épisodes locaux pour analyser cette saison.');
      return;
    }
    final detector = File(p.join(p.dirname(Platform.resolvedExecutable),
        'AnimeOrganizerCreditsDetector.exe'));
    if (!detector.existsSync()) {
      _flash('Analyseur absent. Réinstalle la nouvelle version Windows.');
      return;
    }
    final tempDir = await getTemporaryDirectory();
    final input = File(p.join(tempDir.path,
        'anime_credits_${DateTime.now().microsecondsSinceEpoch}.json'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 5),
        content: Text('Analyse des épisodes en cours… Les vidéos restent sur le PC.')));
    }
    try {
      await input.writeAsString(jsonEncode({'paths': samples}));
      final output = await Process.run(detector.path, [input.path])
          .timeout(const Duration(minutes: 7));
      final data = jsonDecode(output.stdout.toString()) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        _flash('Détection indisponible : ${data['error'] ?? 'erreur inconnue'}');
        return;
      }
      final marks = Map<String, dynamic>.from(data['proposals'] as Map? ?? {});
      if (marks.isEmpty) {
        _flash('Aucun générique commun assez fiable détecté. Repères manuels disponibles.');
        return;
      }
      int? proposal(String key) {
        final raw = marks[key];
        if (raw is! Map) return null;
        return raw['milliseconds'] is int ? raw['milliseconds'] as int : null;
      }
      String pretty(int? value) => value == null ? 'Non détecté' :
          '${value ~/ 60000}:${((value ~/ 1000) % 60).toString().padLeft(2, '0')}';
      final intro = proposal('introEnd');
      final outro = proposal('outroStart');
      final accepted = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Palette.surface,
          title: const Text('Suggestions de génériques'),
          content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Saison $season · ${data['analyzed']} épisodes comparés'),
              const SizedBox(height: 12),
              Text('Fin du générique de début : ${pretty(intro)}'),
              Text('Début du générique de fin : ${pretty(outro)}'),
              const SizedBox(height: 12),
              const Text('Vérifie ces horaires. Une ouverture différente ou une scène répétée peut tromper la détection.'),
            ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Appliquer à la saison')),
          ],
        ));
      if (accepted != true || !mounted) return;
      final anime = widget.anime!;
      if (intro != null) anime.setCreditMarker(current, true, 'introEnd', intro);
      if (outro != null) anime.setCreditMarker(current, true, 'outroStart', outro);
      await library.save();
      library.refresh();
      _flash('Repères proposés enregistrés pour la saison $season.');
    } on TimeoutException {
      if (mounted) _flash('Analyse interrompue : délai dépassé.');
    } catch (e) {
      if (mounted) _flash('Analyse impossible : $e');
    } finally {
      try { if (await input.exists()) await input.delete(); } catch (_) {}
    }
  }

'''
s=replace_one(s,"  void _openOptions() {",method+"  void _openOptions() {",str(player))
old="""                  OutlinedButton.icon(
                    onPressed: () { Navigator.pop(ctx); _openCreditMarkers(); },
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Définir les repères de génériques'),
                  ),"""
new=old+"""
                  if (Platform.isWindows && widget.anime != null)
                    OutlinedButton.icon(
                      onPressed: () { Navigator.pop(ctx); _detectCreditsAutomatically(); },
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Détecter automatiquement (3 épisodes minimum)'),
                    ),"""
s=replace_one(s,old,new,str(player))
step="""      - name: Compresser l'application
        shell: pwsh"""
stepNew="""      - name: Construire l'analyseur local de génériques
        shell: pwsh
        run: |
          python -m PyInstaller --onefile --noconsole --clean --name AnimeOrganizerCreditsDetector tool/credits_detector.py
          Copy-Item dist/AnimeOrganizerCreditsDetector.exe build/windows/x64/runner/Release/AnimeOrganizerCreditsDetector.exe -Force
          if (-not (Test-Path build/windows/x64/runner/Release/AnimeOrganizerCreditsDetector.exe)) { throw 'Analyseur absent' }

"""+step
w=replace_one(w,step,stepNew,str(workflow))
# Write only after both files patch successfully.
player.write_text(s,encoding='utf-8')
workflow.write_text(w,encoding='utf-8')
print('V19 : lecteur Flutter et construction Windows modifiés.')
