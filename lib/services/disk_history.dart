import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Historique local de diagnostics Windows, séparé de la bibliothèque.
/// Aucune écriture sur les disques examinés : seulement un petit fichier JSON
/// dans les données de l'application.
class DiskHistory {
  final Map<String, List<Map<String, dynamic>>> samples = {};
  bool loaded = false;
  String? storageError;

  static String identity(Map<String, dynamic> disk) =>
      '${disk['name'] ?? ''}|${disk['size'] ?? ''}|${disk['type'] ?? ''}';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'disk_health_history.json'));
  }

  Future<void> load() async {
    if (loaded) return;
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map && raw['disks'] is Map) {
          for (final entry in (raw['disks'] as Map).entries) {
            if (entry.value is List) {
              samples[entry.key.toString()] = (entry.value as List)
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList();
            }
          }
        }
      }
    } catch (e) {
      storageError = 'Historique non lisible : $e';
    }
    loaded = true;
  }

  List<Map<String, dynamic>> forDisk(Map<String, dynamic> disk) =>
      samples[identity(disk)] ?? const [];

  int? _count(dynamic value) => value is num ? value.toInt() : int.tryParse('$value');

  /// Détecte les hausses de compteurs, sans confondre valeur totale et nouvelles
  /// erreurs. À la première mesure, aucun delta n'est inventé.
  List<String> append(List<Map<String, dynamic>> disks, DateTime timestamp) {
    final warnings = <String>[];
    final cutoff = timestamp.subtract(const Duration(days: 90)).millisecondsSinceEpoch;
    for (final disk in disks) {
      final key = identity(disk);
      final old = samples.putIfAbsent(key, () => []);
      final prior = old.isEmpty ? null : old.last;
      final name = '${disk['name'] ?? 'Disque'}';
      for (final field in ['readErrorsUncorrected', 'writeErrorsUncorrected']) {
        final before = prior == null ? null : _count(prior[field]);
        final now = _count(disk[field]);
        if (before != null && now != null && now > before) {
          warnings.add('$name : augmentation des erreurs non corrigées (${field == 'readErrorsUncorrected' ? 'lecture' : 'écriture'} : +${now - before}). Sauvegarde conseillée.');
        }
      }
      final beforeHealth = prior == null ? '' : '${prior['health'] ?? ''}'.toLowerCase();
      final nowHealth = '${disk['health'] ?? ''}'.toLowerCase();
      if (prior != null && beforeHealth == 'healthy' && nowHealth != 'healthy') {
        warnings.add('$name : état SMART passé de Healthy à ${disk['health'] ?? 'inconnu'}. Vérifie ta sauvegarde.');
      }
      final temp = _count(disk['temperature']);
      final kind = '${disk['type'] ?? ''}'.toLowerCase();
      // Seuils de vigilance indicatifs, pas limites constructeur.
      if (temp != null && ((kind.contains('ssd') && temp >= 70) || (!kind.contains('ssd') && temp >= 55))) {
        warnings.add('$name : température élevée ($temp °C). Vérifie la ventilation et les recommandations constructeur.');
      }
      final point = <String, dynamic>{
        'at': timestamp.millisecondsSinceEpoch,
        for (final field in ['temperature', 'wear', 'health',
          'readErrorsUncorrected', 'writeErrorsUncorrected']) field: disk[field],
      };
      // Ne pas accumuler des relevés quasi identiques plus d'une fois/minute.
      if (prior == null || timestamp.millisecondsSinceEpoch - (_count(prior['at']) ?? 0) >= 60000) {
        old.add(point);
      } else {
        old[old.length - 1] = point;
      }
      old.removeWhere((s) => (_count(s['at']) ?? 0) < cutoff);
      if (old.length > 1000) old.removeRange(0, old.length - 1000);
    }
    return warnings;
  }

  Future<void> save() async {
    try {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode({'version': 1, 'disks': samples}), flush: true);
      // Sur Windows, un renommage remplaçant le fichier existant peut échouer.
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      storageError = null;
    } catch (e) {
      storageError = 'Impossible d’enregistrer l’historique : $e';
    }
  }
}
