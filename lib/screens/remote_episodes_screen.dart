import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../models/anime.dart';
import 'player_screen.dart';

/// Remote videos are streamed (HTTP Range), never copied to the phone.
/// Credentials are sent in headers only; video URLs use expiring HMAC tickets.
class RemoteEpisodesScreen extends StatefulWidget {
  final String host;
  final String pairCode;
  final int seriesId;
  final String seriesTitle;

  const RemoteEpisodesScreen({super.key, required this.host,
    required this.pairCode, required this.seriesId, required this.seriesTitle});

  @override
  State<RemoteEpisodesScreen> createState() => _RemoteEpisodesScreenState();
}

class _RemoteEpisodesScreenState extends State<RemoteEpisodesScreen> {
  bool _busy = true;
  String _quality = 'direct';
  bool _ffmpegAvailable = false;
  String _serverCapabilities = 'Vérification des qualités en cours…';
  String? _error;
  List<Map<String, dynamic>> _episodes = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadCapabilities();
  }

  Uri _endpoint(String path, Map<String, String> params) =>
    Uri.http('${widget.host}:8765', path, params);

  Future<void> _loadCapabilities() async {
    try {
      final response = await http.get(_endpoint('/v1/capabilities', {}),
          headers: {'X-Anime-Pair-Code': widget.pairCode})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _ffmpegAvailable = data['ffmpeg'] == true;
        _serverCapabilities = '${data['message'] ?? 'État du serveur inconnu.'}';
        if (!_ffmpegAvailable) _quality = 'direct';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ffmpegAvailable = false;
        _quality = 'direct';
        _serverCapabilities = 'Diagnostic indisponible : seul le mode original est proposé.';
      });
    }
  }

  Future<void> _load() async {
    try {
      final r = await http.get(_endpoint('/v1/episodes',
          {'series': '${widget.seriesId}'}),
          headers: {'X-Anime-Pair-Code': widget.pairCode})
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      _episodes = (data['episodes'] as List? ?? [])
          .whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
    } catch (e) {
      _error = 'Épisodes indisponibles : $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(Map<String, dynamic> episode) async {
    final index = episode['id'];
    if (index is! int) return;
    setState(() => _busy = true);
    try {
      final r = await http.get(_endpoint('/v1/ticket',
          {'series': '${widget.seriesId}', 'episode': '$index'}),
          headers: {'X-Anime-Pair-Code': widget.pairCode})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('Vidéo indisponible (HTTP ${r.statusCode})');
      final ticket = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final path = ticket['path'];
      final expiry = ticket['expires'];
      final signature = ticket['signature'];
      if (path is! String || !path.startsWith('/v1/stream/') ||
          expiry is! int || signature is! String) {
        throw Exception('Ticket de lecture invalide');
      }
      final requestedPath = _quality == 'direct'
          ? path : path.replaceFirst('/v1/stream/', '/v1/transcode/');
      final url = _endpoint(requestedPath, {
        if (_quality != 'direct') 'quality': _quality,
        'expires': '$expiry', 'signature': signature,
      }).toString();
      if (!mounted) return;
      final resume = episode['resumeMs'] is int ? episode['resumeMs'] as int : 0;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(
        title: widget.seriesTitle,
        startAt: Duration(milliseconds: resume > 0 ? resume : 0),
        onRemoteProgress: (position, duration, completed) async {
          try {
            await http.post(_endpoint('/v1/progress', {}),
              headers: {'X-Anime-Pair-Code': widget.pairCode,
                        'Content-Type': 'application/json'},
              body: jsonEncode({'series': widget.seriesId, 'episode': index,
                'positionMs': position.inMilliseconds,
                'durationMs': duration.inMilliseconds, 'completed': completed}),
            ).timeout(const Duration(seconds: 6));
          } catch (_) { /* Une perte réseau ne doit pas interrompre le lecteur. */ }
        },
        episodes: [Episode(path: url, name: '${episode['name'] ?? 'Épisode'}',
          season: episode['season'] as int?, number: episode['number'] as int?)],
      )));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Lecture impossible : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: darkAppBar(title: Text(widget.seriesTitle)),
    body: _busy && _episodes.isEmpty
      ? const Center(child: CircularProgressIndicator())
      : _error != null
        ? Center(child: Text(_error!))
        : Column(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Text('Qualité : '),
                const SizedBox(width: 8),
                Expanded(child: DropdownButton<String>(isExpanded: true,
                  value: _quality,
                  items: [
                    const DropdownMenuItem(value: 'direct', child: Text('Originale (sans conversion)')),
                    if (_ffmpegAvailable) const DropdownMenuItem(value: '720', child: Text('720p mobile (FFmpeg)')),
                    if (_ffmpegAvailable) const DropdownMenuItem(value: '480', child: Text('480p économique (FFmpeg)')),
                  ],
                  onChanged: _busy ? null : (v) { if (v != null) setState(() => _quality = v); },
                )),
              ])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_serverCapabilities,
                style: TextStyle(color: _ffmpegAvailable ? Palette.muted : Palette.kin)),
            ),
            Expanded(child: ListView.builder(
            itemCount: _episodes.length,
            itemBuilder: (context, i) {
              final e = _episodes[i];
              final available = e['available'] == true;
              final season = e['season'];
              final number = e['number'];
              return ListTile(
                leading: Icon(available ? Icons.play_circle_outline : Icons.block,
                  color: available ? Palette.kin : Palette.muted),
                title: Text('${e['name'] ?? 'Épisode'}'),
                subtitle: Text('Saison ${season ?? 1} · Épisode ${number ?? i + 1}'
                  '${e['watchedRemote'] == true ? ' · Vu sur téléphone' :
                    (e['resumeMs'] is int && (e['resumeMs'] as int) > 0 ? ' · Reprise disponible' : '')}'),
                onTap: !available || _busy ? null : () => _play(e),
              );
            })),
          ]),
  );
}
