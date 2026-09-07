import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../main.dart';
import '../models/anime.dart';

class PlayerScreen extends StatefulWidget {
  final String title;
  final List<Episode> episodes;
  final int startIndex;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.episodes,
    this.startIndex = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex;
    _player.open(
      Playlist(
        widget.episodes.map((e) => Media(Uri.file(e.path).toString())).toList(),
        index: widget.startIndex,
      ),
    );
    _player.stream.playlist.listen((event) {
      if (mounted && event.index != _index) {
        setState(() => _index = event.index);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.episodes.isEmpty
        ? widget.title
        : widget.episodes[_index.clamp(0, widget.episodes.length - 1)].name;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(current, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.episodes.length > 1)
            IconButton(
              tooltip: 'Épisode precedent',
              onPressed: () => _player.previous(),
              icon: const Icon(Icons.skip_previous),
            ),
          if (widget.episodes.length > 1)
            IconButton(
              tooltip: 'Épisode suivant',
              onPressed: () => _player.next(),
              icon: const Icon(Icons.skip_next),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Video(
              controller: _controller,
              controls: AdaptiveVideoControls,
              fit: BoxFit.contain,
            ),
          ),
          if (widget.episodes.length > 1)
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: widget.episodes.length,
                itemBuilder: (context, i) {
                  final selected = i == _index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: GestureDetector(
                      onTap: () => _player.jump(i),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: selected ? Palette.shu : Palette.raised,
                          borderRadius: BorderRadius.circular(radiusMd),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: selected ? Colors.white : Palette.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
