import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Catalogue distant : il n'est jamais fusionné avec les chemins locaux.
/// Le cache conserve uniquement les métadonnées, pas les codes d'association.
class RemoteLibrary extends ChangeNotifier {
  String host = '';
  String pairCode = '';
  bool connected = false;
  bool loading = false;
  bool initialized = false;
  String error = '';
  List<Map<String, dynamic>> series = [];

  Future<File> _file(String name) async => File(p.join(
      (await getApplicationSupportDirectory()).path, name));

  Future<void> initialize() async {
    if (!Platform.isAndroid || initialized) return;
    initialized = true;
    try {
      final pairing = jsonDecode(await (await _file('android_pc_pair_v39.json')).readAsString());
      if (pairing is Map && pairing['host'] is String && pairing['code'] is String) {
        host = pairing['host'] as String;
        pairCode = pairing['code'] as String;
      }
    } catch (_) {}
    try {
      final cache = jsonDecode(await (await _file('remote_catalog_v40.json')).readAsString());
      if (cache is Map && cache['host'] == host && host.isNotEmpty &&
          cache['series'] is List) {
        series = _decodeSeries(cache['series'] as List);
        notifyListeners();
      }
    } catch (_) {}
    if (host.isNotEmpty && pairCode.isNotEmpty) {
      await refresh();
    }
  }

  List<Map<String, dynamic>> _decodeSeries(List items) => items
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .where((item) => item['id'] is int)
      .toList();

  /// Le panneau Synchronisation vient de valider le catalogue : éviter
  /// une seconde requête réseau et publier directement le résultat à l'accueil.
  Future<void> useCatalogue(String newHost, String code,
      List<Map<String, dynamic>> catalogue) async {
    host = newHost;
    pairCode = code;
    initialized = true;
    series = _decodeSeries(catalogue);
    connected = true;
    error = '';
    notifyListeners();
    try {
      await (await _file('remote_catalog_v40.json')).writeAsString(
          jsonEncode({'host': host, 'series': series}), flush: true);
    } catch (_) {}
  }

  Future<void> refresh() async {
    if (loading || host.isEmpty || pairCode.isEmpty) return;
    loading = true;
    error = '';
    notifyListeners();
    try {
      final response = await http.get(Uri.http('$host:8765', '/v1/library'),
        headers: {'X-Anime-Pair-Code': pairCode})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(response.statusCode == 401
            ? 'Code d’association refusé' : 'HTTP ${response.statusCode}');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['series'] is! List) {
        throw const FormatException('Catalogue invalide');
      }
      series = _decodeSeries(data['series'] as List);
      connected = true;
      try {
        await (await _file('remote_catalog_v40.json')).writeAsString(
            jsonEncode({'host': host, 'series': series}), flush: true);
      } catch (_) { /* Le catalogue reste visible dans cette session. */ }
    } catch (e) {
      connected = false;
      error = '$e'; // Conserver la liste en cache, mais pas la lecture hors ligne.
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

final remoteLibrary = RemoteLibrary();
