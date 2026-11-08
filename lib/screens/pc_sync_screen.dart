import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/library_controller.dart';
import '../services/remote_library.dart';
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
  bool _serverReady = false;
  String _pairCode = '';
  String _ip = '';
  String _tailHost = ''; // V39_REMOTE_TAILSCALE: stable PC name across networks.
  String _message = '';
  bool _busy = false;
  List<Map<String, dynamic>> _remote = [];

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _findIp();
      unawaited(_detectTailHost());
      unawaited(_checkRunningServer());
    } else {
      unawaited(_restorePairing());
    }
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

  // V39_REMOTE_TAILSCALE: a private tailnet, not an Internet port exposure.
  Future<String> _detectTailHost() async {
    if (!Platform.isWindows) return '';
    final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final candidates = <String>[
      p.join(programFiles, 'Tailscale', 'tailscale.exe'),
      'tailscale',
    ];
    for (final exe in candidates) {
      try {
        final result = await Process.run(exe, ['status', '--json'])
            .timeout(const Duration(seconds: 5));
        if (result.exitCode != 0) continue;
        final data = jsonDecode(result.stdout.toString());
        if (data is! Map || data['BackendState'] != 'Running') continue;
        final self = data['Self'];
        if (self is! Map) continue;
        var host = (self['DNSName'] ?? '').toString().trim();
        if (host.endsWith('.')) host = host.substring(0, host.length - 1);
        if (host.isEmpty) {
          final ips = self['TailscaleIPs'];
          if (ips is List) {
            for (final ip in ips) {
              if (ip.toString().startsWith('100.')) {
                host = ip.toString();
                break;
              }
            }
          }
        }
        if (mounted) setState(() => _tailHost = host);
        return host;
      } catch (_) { /* Tailscale absent: manual troubleshooting remains. */ }
    }
    if (mounted) setState(() => _tailHost = '');
    return '';
  }

  Future<File> _pairingFile(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, name));
  }

  // Same 12-character code across server restarts, allowing reconnect.
  // Private app support file, never part of the user's Git repository.
  Future<String> _savedServerCode() async {
    final file = await _pairingFile('pc_sync_pair_v39.json');
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['code'] is String &&
          RegExp(r'^[A-Z2-9]{12}$').hasMatch(data['code'] as String)) {
        return data['code'] as String;
      }
    } catch (_) {}
    final token = _newCode();
    await file.writeAsString(jsonEncode({'code': token}), flush: true);
    return token;
  }

  Future<void> _restorePairing() async {
    try {
      final file = await _pairingFile('android_pc_pair_v39.json');
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      final host = '${data['host'] ?? ''}';
      final code = '${data['code'] ?? ''}';
      if (!_validHost(host) || code.length != 12 || !mounted) return;
      _address.text = host;
      _code.text = code;
      setState(() => _message = 'PC memorise : connexion en cours...');
      await _connect();
    } catch (_) { /* First use: no saved pairing. */ }
  }

  bool _validHost(String host) =>
      RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(host) && host.length <= 253;

  Future<void> _pasteInvitation() async {
    final value = (await Clipboard.getData('text/plain'))?.text?.trim() ?? '';
    final parts = value.split('|');
    if (parts.length != 3 || parts[0] != 'AO39' ||
        !_validHost(parts[1]) || !RegExp(r'^[A-Z2-9]{12}$').hasMatch(parts[2])) {
      if (mounted) setState(() => _message =
        'Invitation introuvable. Copie-la sur Windows et colle-la ici.');
      return;
    }
    _address.text = parts[1];
    _code.text = parts[2];
    await _connect();
  }

  Future<void> _copyInvitation() async {
    final host = _tailHost;
    if (host.isEmpty || _pairCode.isEmpty) {
      if (mounted) setState(() => _message =
        'Active Tailscale sur Windows puis demarre le serveur.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: 'AO39|$host|$_pairCode'));
    if (mounted) setState(() => _message =
      'Invitation copiee. Elle contient le code secret : ne la partage pas publiquement.');
  }

  String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(12, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  // Reattach after navigation or an app restart without spawning duplicates.
  Future<void> _checkRunningServer() async {
    if (!Platform.isWindows) return;
    try {
      final token = await _savedServerCode();
      final active = await _ping('127.0.0.1', token);
      if (!mounted) return;
      setState(() {
        _serverReady = active;
        if (active) {
          _pairCode = token;
          _message = 'Serveur deja actif : connexion conservee.';
        }
      });
    } catch (_) { /* No companion running yet. */ }
  }

  Future<void> _stopServer() async {
    if (_busy || !_serverReady) return;
    setState(() => _busy = true);
    try {
      if (_server != null) {
        final child = _server!;
        child.kill();
        try {
          await child.exitCode.timeout(const Duration(seconds: 3));
        } catch (_) {}
        _server = null;
      } else if (Platform.isWindows) {
        // Only our named helper; the Python side enforces one instance.
        await Process.run('taskkill', ['/IM', 'AnimeOrganizerSyncServer.exe', '/F']);
      }
      if (mounted) setState(() {
        _serverReady = false;
        _pairCode = '';
        _message = 'Serveur arrete manuellement.';
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'Arret impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || _serverReady) return;
    setState(() => _busy = true);
    try {
      final exe = p.join(p.dirname(Platform.resolvedExecutable), 'AnimeOrganizerSyncServer.exe');
      if (!File(exe).existsSync()) {
        throw Exception('Serveur absent de cette installation Windows. Réinstalle la nouvelle version complète.');
      }
      final dir = await getApplicationSupportDirectory();
      final lib = p.join(dir.path, 'library.json');
      if (!File(lib).existsSync()) throw Exception('Bibliothèque introuvable sur ce PC.');
      final token = await _savedServerCode();
      await _detectTailHost();
      // An already-running companion must be reused, never started again.
      if (await _ping('127.0.0.1', token)) {
        _serverReady = true;
        _pairCode = token;
        _message = 'Serveur deja actif : connexion conservee.';
        return;
      }
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
        _serverReady = true;
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
    if (!_validHost(host) || token.length != 12) {
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
      // L'accueil affiche désormais aussi le catalogue distant.
      await remoteLibrary.useCatalogue(host, token, _remote);
      _message = '${_remote.length} séries reçues depuis le PC. Aucune vidéo transférée.';
      if (Platform.isAndroid) {
        final saved = await _pairingFile('android_pc_pair_v39.json');
        await saved.writeAsString(jsonEncode({'host': host, 'code': token}), flush: true);
      }
    } catch (e) {
      _message = 'Connexion impossible : $e. Verifie que Tailscale est connecte sur les deux appareils, que le PC est allume et que le serveur tourne.';
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

  Future<void> _importRemotePlayback() async {
    if (!Platform.isWindows || _busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getApplicationSupportDirectory();
      final path = p.join(dir.path, 'library.json.remote_progress.json');
      final file = File(path);
      if (!file.existsSync()) {
        _message = 'Aucune progression Android à importer.';
        return;
      }
      final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      var imported = 0;
      for (final value in payload.values) {
        if (value is! Map) continue;
        final folder = '${value['folderTitle'] ?? ''}';
        final matches = library.animes.where((a) => a.folderTitle == folder).toList();
        if (matches.length != 1) continue;
        final item = matches.single;
        final candidates = item.episodes.where((e) =>
          (e.season ?? 1) == value['season'] && e.number == value['number'] &&
          e.name == value['name']).toList();
        if (candidates.length != 1) continue;
        final episode = candidates.single;
        final updated = value['updatedAtMs'];
        if (updated is! int || updated <= (item.lastPlayedAtMs ?? 0)) continue;
        final watched = value['watched'] == true;
        final position = value['positionMs'];
        if (position is! int || position < 0) continue;
        item.lastEpisodePath = episode.path;
        item.lastPositionMs = watched ? 0 : position;
        item.lastPlayedAtMs = updated;
        if (watched && !item.watchedPaths.contains(episode.path)) {
          item.watchedPaths.add(episode.path);
        }
        imported++;
      }
      if (imported > 0) {
        await library.save();
        library.refresh();
      }
      _message = '$imported progression(s) Android importée(s) sur Windows.';
    } catch (e) {
      _message = 'Import impossible : $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Guide first connection: public, official Tailscale downloads only.
  Future<void> _openTailscale(String url) async {
    final uri = Uri.parse(url);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d’ouvrir le lien : $url')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d’ouvrir le lien : $url')),
        );
      }
    }
  }

  Widget _tailscaleGuide(bool windows) {
    final steps = windows
        ? <String>[
            'Installe Tailscale sur ce PC Windows, puis connecte-toi à ton compte.',
            'Installe Tailscale sur le téléphone et utilise le même compte.',
            'Vérifie que Tailscale indique « Connecté » sur les deux appareils.',
            'Dans Anime Organizer sur PC, clique sur « Démarrer le serveur ».',
            'Sur Android, indique l’adresse Tailscale du PC (souvent 100.x.x.x) et le code affiché ici.',
            'Appuie sur « Se connecter ». L’association sera mémorisée.',
          ]
        : <String>[
            'Installe Tailscale sur Android et sur le PC Windows.',
            'Connecte les deux appareils au même compte Tailscale et active la connexion.',
            'Sur le PC, ouvre Anime Organizer > Synchronisation puis « Démarrer le serveur ».',
            'Récupère l’adresse Tailscale du PC (100.x.x.x ou nom .ts.net) et le code d’association.',
            'Saisis-les ci-dessous, puis appuie sur « Se connecter ».',
            'La connexion est mémorisée : tu n’auras normalement pas à retaper le code.',
          ];
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.help_outline),
        title: const Text('Première connexion : petit tuto Tailscale'),
        subtitle: const Text('Installation gratuite et association PC / Android'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          ...steps.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 24, child: Text('${entry.key + 1}.',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(child: Text(entry.value)),
                ]),
              )),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => _openTailscale('https://tailscale.com/download/windows'),
            icon: const Icon(Icons.computer),
            label: const Text('Télécharger Tailscale pour Windows'),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => _openTailscale('https://play.google.com/store/apps/details?id=com.tailscale.ipn'),
            icon: const Icon(Icons.phone_android),
            label: const Text('Installer Tailscale sur Android'),
          ),
          const SizedBox(height: 10),
          const Text('À savoir : le PC doit rester allumé, Anime Organizer doit servir les vidéos et Tailscale doit être connecté sur les deux appareils.'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Keep the companion alive for playback after leaving this page.
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
          ? 'Démarre le serveur sur ton PC, puis saisis les informations affichées dans l’APK Android. Le serveur reste actif quand tu quittes cet écran, pour permettre la lecture à distance.'
          : 'Accede a ton PC de partout via Tailscale, meme en 4G. Colle une invitation une seule fois, puis la connexion est memorisee. Le PC doit rester allume et le serveur demarre.',
          style: TextStyle(color: Palette.muted)),
        const SizedBox(height: 12),
        _tailscaleGuide(windows),
        const SizedBox(height: 20),
        if (windows) ...[
          Text('PC sur Tailscale : ${_tailHost.isEmpty ? 'Tailscale non detecte' : _tailHost}'),
          const SizedBox(height: 8),
          SelectableText('Code d’association : ${_pairCode.isEmpty ? '—' : _pairCode}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: !_serverReady ? null : _copyInvitation,
            icon: const Icon(Icons.copy_all),
            label: const Text("Copier l'invitation pour Android"),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importRemotePlayback,
            icon: const Icon(Icons.download_done),
            label: const Text('Importer les lectures effectuées sur Android'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : (_serverReady ? _stopServer : _start),
            icon: Icon(_serverReady ? Icons.stop_circle_outlined : Icons.wifi_tethering),
            label: Text(_serverReady ? 'Arrêter le serveur' : 'Démarrer le serveur'),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: _busy ? null : _pasteInvitation,
            icon: const Icon(Icons.content_paste),
            label: const Text("Coller l'invitation du PC et se connecter"),
          ),
          const SizedBox(height: 12),
          const Text('Connexion manuelle (depannage / Tailscale) :'),
          const SizedBox(height: 8),
          TextField(controller: _address,
            decoration: const InputDecoration(labelText: 'Nom Tailscale du PC', hintText: 'mon-pc.exemple.ts.net')),
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
