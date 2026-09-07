import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';

/// Explorateur de dossiers maison.
/// Ecrit avec dart:io uniquement : pas de plugin natif, donc le meme
/// comportement sur Windows et sur Android, et rien a maintenir cote Gradle.
class FolderPickerScreen extends StatefulWidget {
  final String? initialPath;
  const FolderPickerScreen({super.key, this.initialPath});

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  String? _current;
  List<Directory> _children = [];
  List<_Root> _roots = [];
  String? _error;
  bool _allFilesGranted = true;

  @override
  void initState() {
    super.initState();
    _roots = _listRoots();
    _checkPermission();
    final start = widget.initialPath;
    if (start != null && Directory(start).existsSync()) {
      _open(start);
    } else if (_roots.length == 1) {
      _open(_roots.first.path);
    }
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) return;
    final granted = await Permission.manageExternalStorage.isGranted;
    if (!mounted) return;
    setState(() => _allFilesGranted = granted);
  }

  Future<void> _requestAllFiles() async {
    await Permission.manageExternalStorage.request();
    await _checkPermission();
    if (!mounted) return;
    setState(() => _roots = _listRoots());
  }

  /// Points de depart proposes selon la plateforme.
  List<_Root> _listRoots() {
    final roots = <_Root>[];
    if (Platform.isAndroid) {
      for (final candidate in const [
        ['/storage/emulated/0', 'Memoire interne'],
        ['/storage/emulated/0/Download', 'Telechargements'],
        ['/storage/emulated/0/Movies', 'Videos'],
        ['/storage/emulated/0/DCIM', 'DCIM'],
      ]) {
        if (Directory(candidate[0]).existsSync()) {
          roots.add(_Root(candidate[0], candidate[1]));
        }
      }
      // Cartes SD et cles USB : on les propose meme si elles ne sont pas
      // encore lisibles, sinon elles disparaissent tant que l'autorisation
      // « tous les fichiers » n'est pas accordee.
      for (final base in const ['/storage', '/mnt/media_rw']) {
        try {
          for (final e in Directory(base).listSync()) {
            if (e is! Directory) continue;
            final name = p.basename(e.path);
            if (name == 'emulated' || name == 'self') continue;
            if (roots.any((r) => r.path == e.path)) continue;
            roots.add(_Root(
              e.path,
              name.contains('-') ? 'Carte SD ($name)' : 'Volume $name',
              readable: _canList(e.path),
            ));
          }
        } catch (_) {}
      }
    } else if (Platform.isWindows) {
      for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final drive = '${String.fromCharCode(c)}:\\';
        if (Directory(drive).existsSync()) {
          roots.add(_Root(drive, 'Disque ${String.fromCharCode(c)}'));
        }
      }
    } else {
      roots.add(_Root('/', 'Racine'));
      final home = Platform.environment['HOME'];
      if (home != null && Directory(home).existsSync()) {
        roots.add(_Root(home, 'Dossier personnel'));
      }
    }
    return roots;
  }

  bool _canList(String path) {
    try {
      Directory(path).listSync().take(1).toList();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _open(String path) {
    try {
      final dirs = Directory(path)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith('.'))
          .toList()
        ..sort((a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()));
      setState(() {
        _current = path;
        _children = dirs;
        _error = null;
      });
    } catch (_) {
      setState(() {
        _current = path;
        _children = [];
        _error = 'Dossier illisible. Verifie les autorisations de stockage.';
      });
    }
  }

  void _goUp() {
    final current = _current;
    if (current == null) return;
    final parent = p.dirname(current);
    if (parent == current) {
      setState(() => _current = null);
    } else if (Directory(parent).existsSync()) {
      _open(parent);
    } else {
      setState(() => _current = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;

    return Scaffold(
      appBar: darkAppBar(
        title: Text(
          current == null ? 'Choisir un emplacement' : p.basename(current),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (current != null)
            IconButton(
              tooltip: 'Dossier parent',
              onPressed: _goUp,
              icon: const Icon(Icons.arrow_upward),
            ),
        ],
      ),
      floatingActionButton: current == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context, current),
              backgroundColor: Palette.shu,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.check),
              label: const Text('Choisir ce dossier'),
            ),
      body: current == null ? _rootList() : _folderList(current),
    );
  }

  Widget _rootList() {
    if (_roots.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aucun emplacement accessible. Accorde l\'acces au stockage puis reviens ici.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (!_allFilesGranted) _permissionBanner(),
        for (final r in _roots)
          ListTile(
            leading: Icon(Icons.storage,
                color: r.readable ? Palette.asagi : Palette.muted),
            title: Text(r.label),
            subtitle: Text(
              r.readable ? r.path : '${r.path} — acces refuse pour l instant',
              style: TextStyle(
                color: r.readable ? Palette.muted : Palette.shu,
                fontSize: 11.5,
              ),
            ),
            onTap: () => _open(r.path),
          ),
        ListTile(
          leading: const Icon(Icons.keyboard, color: Palette.muted),
          title: const Text('Saisir un chemin'),
          subtitle: const Text('Si un volume n apparait pas dans la liste',
              style: TextStyle(color: Palette.muted, fontSize: 11.5)),
          onTap: _manualPath,
        ),
      ],
    );
  }

  Widget _permissionBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.raised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Acces a tous les fichiers desactive',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sans cette autorisation, la carte SD et certains dossiers restent invisibles.',
            style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _requestAllFiles,
            style: FilledButton.styleFrom(backgroundColor: Palette.shu),
            child: const Text('Autoriser'),
          ),
        ],
      ),
    );
  }

  Future<void> _manualPath() async {
    final controller = TextEditingController(
      text: Platform.isAndroid ? '/storage/' : '',
    );
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Saisir un chemin'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: fieldDecoration(hintText: '/storage/1A2B-3C4D/Animes'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return;
    _open(path);
  }

  Widget _folderList(String current) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            current,
            style: const TextStyle(color: Palette.muted, fontSize: 12),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_error!,
                style: const TextStyle(color: Palette.shu, fontSize: 13)),
          ),
        Expanded(
          child: _children.isEmpty
              ? const Center(
                  child: Text('Aucun sous-dossier ici.',
                      style: TextStyle(color: Palette.muted)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: _children.length,
                  itemBuilder: (context, i) {
                    final d = _children[i];
                    return ListTile(
                      leading:
                          const Icon(Icons.folder_outlined, color: Palette.asagi),
                      title: Text(p.basename(d.path),
                          style: const TextStyle(fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right,
                          color: Palette.muted, size: 20),
                      onTap: () => _open(d.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Root {
  final String path;
  final String label;
  final bool readable;
  const _Root(this.path, this.label, {this.readable = true});
}
