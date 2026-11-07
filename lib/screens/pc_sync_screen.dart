import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../main.dart';
import '../services/library_controller.dart';
import 'remote_episodes_screen.dart';

/// Windows: launches the bundled Python companion. Android: LAN catalogue and
/// conservative progress import. No media content or PC file paths cross LAN.
class PcSyncScreen extends StatefulWidget {
  const PcSyncScreen({super.key});
  @override
  State<PcSyncScreen> createState() => _PcSyncScreenState();
}

class _PcSyncScreenState extends State<PcSyncScreen> {
  static const _port = 8765;
  final _address = TextEditingController();
  final _code = TextEditingController();
  Process? _server;
  String _pairCode = '';
  String _ip = '';
  String _message = '';
  bool _busy = false;
  List<Map<String, dynamic>> _remote = [];

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) _findIp();
  }

  Future<void> _findIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final n in interfaces) {
        for (final a in n.addresses) {
          if (!a.isLoopback && !a.address.startsWith('169.254.')) {
            if (mounted) setState(() => _ip = a.address);
            return;
          }
        }
      }
    } catch (_) {}
  }

  String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(12, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  Future<void> _start() async {
    if (_busy || _server != null) return;
    setState(() => _busy = true);
    try {
      final exe = p.join(p.dirname(Platform.resolvedExecutable), 'AnimeOrganizerSyncServer.exe');
      if (!File(exe).existsSync()) {
        throw Exception('Serveur absent de cette installation Windows. Réinstalle la nouvelle version complète.');
      }
      final dir = await getApplicationSupportDirectory();
      final lib = p.join(dir.path, 'library.json');
      if (!File(lib).existsSync()) throw Exception('Bibliothèque introuvable sur ce PC.');
      final token = _newCode();
      final child = await Process.start(exe, [
        '--library', lib, '--token', token, '--port', '$_port'
      ], mode: ProcessStartMode.normal);
      var ready = false;
      for (var attempt = 0; attempt < 12; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (await _ping('127.0.0.1', token)) { ready = true; break; }
      }
      if (ready) {
        _server = child;
        _pairCode = token;
        _message = 'Serveur démarré. Autorise la connexion réseau privé si Windows le demande.';
      } else {
        child.kill();
        _message = 'Le serveur ne répond pas. Le port $_port est peut-être déjà utilisé.';
      }
    } catch (e) {
      _message = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _ping(String host, String token) async {
    try {
      final res = await http.get(Uri.http('$host:$_port', '/v1/ping'),
        headers: {'X-Anime-Pair-Code': token})
        .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<void> _connect() async {
    if (_busy) return;
    final host = _address.text.trim();
    final token = _code.text.trim().toUpperCase();
    if (!RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(host) || token.length < 10) {
      setState(() => _message = 'Entre l’adresse IP locale du PC et son code d’association.');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await http.get(Uri.http('$host:$_port', '/v1/library'),
        headers: {'X-Anime-Pair-Code': token})
        .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception(
        res.statusCode == 401 ? 'Code d’association incorrect.' : 'Réponse du serveur : ${res.statusCode}');
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final items = body['series'] as List? ?? [];
      _remote = items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _message = '${_remote.length} séries reçues depuis le PC. Aucune vidéo transférée.';
    } catch (e) {
      _message = 'Connexion impossible : $e. Vérifie le même Wi-Fi et le pare-feu Windows.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _normalize(String value) => value.toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> _importProgress() async {
    if (_remote.isEmpty) return;
    var added = 0;
    var matched = 0;
    for (final item in _remote) {
      // Match the original folder title, not potentially incorrect API data.
      // Prevents importing progress into a series wrongly labelled DBZ.
      final folder = _normalize('${item['folderTitle'] ?? ''}');
      if (folder.length < 5) continue;
      final candidates = library.animes.where((a) =>
          _normalize(a.folderTitle) == folder).toList();
      if (candidates.length != 1) continue;
      final local = candidates.single;
      matched++;
      final remoteKeys = (item['watchedKeys'] as List? ?? []).map((x) => '$x').toSet();
      for (final e in local.episodes) {
        if (e.bonus || e.number == null) continue;
        final key = '${e.season ?? 1}:${e.number}';
        if (remoteKeys.contains(key) && !local.watchedPaths.contains(e.path)) {
          local.watchedPaths.add(e.path);
          added++;
        }
      }
    }
    await library.save();
    library.refresh();
    if (mounted) setState(() => _message = '$matched séries locales correspondantes · $added épisodes marqués vus. Les autres restent inchangés.');
  }

  @override
  void dispose() {
    _server?.kill();
    _address.dispose(); _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final windows = Platform.isWindows;
    return Scaffold(
      appBar: darkAppBar(title: const Text('Synchronisation PC / Android')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(windows ? 'Serveur Python intégré' : 'Se connecter au PC',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(windows
          ? 'Démarre le serveur sur ton PC, puis saisis les informations affichées dans l’APK Android. Le serveur s’arrête quand tu quittes cet écran.'
          : 'Connecte les deux appareils au même Wi-Fi ou à ton réseau privé Tailscale. Les vidéos restent sur le PC.',
          style: TextStyle(color: Palette.muted)),
        const SizedBox(height: 20),
        if (windows) ...[
          Text('Adresse du PC : ${_ip.isEmpty ? 'adresse locale non trouvée' : _ip}:$_port'),
          const SizedBox(height: 8),
          SelectableText('Code d’association : ${_pairCode.isEmpty ? '—' : _pairCode}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : (_server == null ? _start : () {
              _server?.kill();
              setState(() { _server = null; _pairCode = ''; _message = 'Serveur arrêté.'; });
            }),
            icon: Icon(_server == null ? Icons.wifi_tethering : Icons.stop_circle_outlined),
            label: Text(_server == null ? 'Démarrer le serveur' : 'Arrêter le serveur'),
          ),
        ] else ...[
          TextField(controller: _address,
            decoration: const InputDecoration(labelText: 'Adresse IP locale du PC', hintText: '192.168.1.20')),
          const SizedBox(height: 12),
          TextField(controller: _code, textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Code d’association (12 caractères)')),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _busy ? null : _connect,
            icon: const Icon(Icons.link), label: const Text('Se connecter et afficher la bibliothèque')),
          if (_remote.isNotEmpty) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: _importProgress,
              icon: const Icon(Icons.sync),
              label: const Text('Importer la progression des épisodes locaux')),
            Text('Catalogue du PC (${_remote.length} séries)',
              style: Theme.of(context).textTheme.titleMedium),
            ..._remote.take(300).map((a) => ListTile(
              title: Text('${a['title'] ?? ''}'),
              subtitle: Text('${a['episodeCount'] ?? 0} épisodes · ${a['watchedCount'] ?? 0} vus sur le PC'),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: a['id'] is int ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RemoteEpisodesScreen(
                  host: _address.text.trim(),
                  pairCode: _code.text.trim().toUpperCase(),
                  seriesId: a['id'] as int,
                  seriesTitle: '${a['title'] ?? ''}',
                ))) : null,
            )),
            if (_remote.length > 300)
              Text('${_remote.length - 300} autres séries non affichées dans cet aperçu.'),
          ],
        ],
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        Text(_message, style: TextStyle(color: Palette.kin)),
      ]),
    );
  }
}
