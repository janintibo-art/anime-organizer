import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

/// Fenêtre secondaire Windows. Son moteur Flutter et son lecteur sont séparés.
/// Les coordonnées temporelles sont transmises au lecteur principal au retour.
class FloatingPlayerWindow extends StatefulWidget {
  final Map<String, dynamic> initial;
  const FloatingPlayerWindow({super.key, required this.initial});

  @override
  State<FloatingPlayerWindow> createState() => _FloatingPlayerWindowState();
}

class _FloatingPlayerWindowState extends State<FloatingPlayerWindow>
    with WindowListener {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  late final List<String> _paths;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Playlist>? _playlistSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Tracks>? _trackSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _index = 0;
  bool _onTop = true;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _paths = (widget.initial['paths'] as List<dynamic>?)
            ?.map((value) => value.toString()).toList() ?? <String>[];
    _index = ((widget.initial['index'] as num?)?.toInt() ?? 0)
        .clamp(0, _paths.isEmpty ? 0 : _paths.length - 1);
    _positionSub = _player.stream.position.listen((p) {
      _position = p;
      if (mounted) setState(() {});
    });
    _playlistSub = _player.stream.playlist.listen((p) {
      if (mounted && p.index != _index) setState(() => _index = p.index);
    });
    _durationSub = _player.stream.duration.listen((d) {
      _duration = d;
      if (mounted) setState(() {});
    });
    // Réappliquer les langues quand mpv a réellement découvert les pistes.
    _trackSub = _player.stream.tracks.listen((tracks) {
      final audio = widget.initial['audio']?.toString().trim().toLowerCase() ?? '';
      final subtitle = widget.initial['subtitle']?.toString().trim().toLowerCase() ?? '';
      if (audio.isNotEmpty) {
        for (final t in tracks.audio) {
          final tag = '${t.language ?? ''} ${t.title ?? ''}'.toLowerCase();
          if (tag.contains(audio) ||
              (audio == 'fr' && (tag.contains('fra') || tag.contains('french'))) ||
              (audio == 'ja' && (tag.contains('jpn') || tag.contains('japanese')))) {
            unawaited(_player.setAudioTrack(t));
            break;
          }
        }
      }
      if (subtitle == 'no') {
        unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));
      } else if (subtitle.isNotEmpty) {
        for (final t in tracks.subtitle) {
          final tag = '${t.language ?? ''} ${t.title ?? ''}'.toLowerCase();
          if (tag.contains(subtitle) ||
              (subtitle == 'fr' && (tag.contains('fra') || tag.contains('french')))) {
            unawaited(_player.setSubtitleTrack(t));
            break;
          }
        }
      }
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await windowManager.setTitle('Anime Organizer · Mini-lecteur');
    await windowManager.setMinimumSize(const Size(280, 195));
    await windowManager.setSize(const Size(460, 320));
    await windowManager.setAlwaysOnTop(true);
    if (_paths.isNotEmpty) {
      await _player.open(Playlist(_paths.map((p) => Media(
          p.startsWith('http://') || p.startsWith('https://')
              ? p : Uri.file(p).toString())).toList(), index: _index));
      final ms = (widget.initial['positionMs'] as num?)?.toInt() ?? 0;
      if (ms > 0) await _player.seek(Duration(milliseconds: ms));
      // Les sous-titres désactivés sont une préférence explicite.
      final subtitle = widget.initial['subtitle']?.toString() ?? '';
      if (subtitle == 'no') await _player.setSubtitleTrack(SubtitleTrack.no());
      final audio = widget.initial['audio']?.toString() ?? '';
      if (audio.isNotEmpty) {
        final tracks = _player.state.tracks.audio;
        for (final track in tracks) {
          if ('${track.language ?? ''} ${track.title ?? ''}'.toLowerCase()
              .contains(audio.toLowerCase())) {
            await _player.setAudioTrack(track);
            break;
          }
        }
      }
    }
  }

  Future<void> _finish({required bool restore}) async {
    if (_closing) return;
    _closing = true;
    try {
      final mainId = widget.initial['mainWindowId']?.toString() ?? '';
      if (mainId.isNotEmpty) {
        final main = WindowController.fromWindowId(mainId);
        await main.invokeMethod(restore ? 'floating_restore' : 'floating_close', {
          'index': _index,
          'positionMs': _player.state.position.inMilliseconds,
          'playing': _player.state.playing,
        });
      }
    } catch (error) {
      // On ne ferme pas une fenêtre si le transfert échoue : la lecture
      // reste visible et l'utilisateur peut réessayer.
      if (mounted) {
        setState(() => _closing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Retour impossible : $error')),
        );
      }
      return;
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() => unawaited(_finish(restore: true));

  @override
  void dispose() {
    windowManager.removeListener(this);
    _positionSub?.cancel();
    _playlistSub?.cancel();
    _durationSub?.cancel();
    _trackSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds;
    final position = _position.inMilliseconds.clamp(0, total > 0 ? total : 0);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Column(children: [
          Expanded(child: Video(controller: _video, controls: NoVideoControls)),
          if (total > 0)
            SizedBox(height: 12, child: Slider(
              value: position.toDouble(), min: 0, max: total.toDouble(),
              onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())),
            )),
          Row(children: [
            IconButton(tooltip: 'Précédent', onPressed: _index > 0
                ? () => _player.previous() : null,
                icon: const Icon(Icons.skip_previous)),
            IconButton(tooltip: 'Lecture / pause',
              onPressed: () async { await _player.playOrPause(); if (mounted) setState(() {}); },
              icon: Icon(_player.state.playing ? Icons.pause : Icons.play_arrow)),
            IconButton(tooltip: 'Suivant', onPressed: _index < _paths.length - 1
                ? () => _player.next() : null,
                icon: const Icon(Icons.skip_next)),
            const Spacer(),
            IconButton(tooltip: _onTop ? 'Désactiver toujours visible' : 'Toujours visible',
              onPressed: () async {
                await windowManager.setAlwaysOnTop(!_onTop);
                if (mounted) setState(() => _onTop = !_onTop);
              }, icon: Icon(_onTop ? Icons.push_pin : Icons.push_pin_outlined)),
            IconButton(tooltip: 'Revenir à Anime Organizer',
              onPressed: _closing ? null : () => _finish(restore: true),
              icon: const Icon(Icons.fullscreen)),
            IconButton(tooltip: 'Arrêter et fermer',
              onPressed: _closing ? null : () => _finish(restore: false),
              icon: const Icon(Icons.close)),
          ]),
        ]),
      ),
    );
  }
}
