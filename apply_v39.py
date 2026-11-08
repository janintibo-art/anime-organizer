#!/usr/bin/env python3
"""Anime Organizer V39: Android AppBar + LAN discovery and opt-in pairing.
Changes apply to existing V38 source files; aborts if anchors differ.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parent

def update(filename, transform):
    path=root/filename
    source=path.read_text(encoding='utf-8')
    patched=transform(source)
    if patched==source: raise SystemExit(f'V39: aucun changement dans {filename}')
    path.write_text(patched,encoding='utf-8',newline='\n')
    print('V39:',filename)

def replace_one(s,old,new,where):
    n=s.count(old)
    if n!=1: raise SystemExit(f'V39: ancre {where}: {n} occurrences (attendu 1)')
    return s.replace(old,new,1)

def home(s):
    start=s.index('            title: Column(\n',s.index('appBar: darkAppBar('))
    end=s.index('          floatingActionButton:',start)
    # Retain original desktop toolbar behavior; use compact Android layout.
    original=s[start:end]
    title=original[:original.index('            actions: [')]
    actions=original[original.index('            actions: ['):]
    title=title.replace("const Text('Anime Organizer'),", "const Flexible(child: Text('Anime Organizer', maxLines: 1, overflow: TextOverflow.ellipsis)),")
    small='''            actions: [
              IconButton(tooltip: 'Connexion au PC', icon: const Icon(Icons.sync_alt),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PcSyncScreen()))),
              PopupMenuButton<String>(tooltip: 'Actions', icon: const Icon(Icons.more_vert),
                onSelected: (value) async {
                  switch (value) {
                    case 'folder': await _addFolder(); break;
                    case 'repair':
                      if (library.busy) return;
                      final count = await library.repairWrongMatches();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('$count fiche(s) corrigée(s).')));
                      break;
                    case 'scan': if (!library.busy) await library.scan(); break;
                    case 'settings':
                      if (!context.mounted) return;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SettingsScreen()));
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'folder', child: Text('Ajouter un dossier')),
                  PopupMenuItem(value: 'repair', child: Text('Vérifier les fiches')),
                  PopupMenuItem(value: 'scan', child: Text('Actualiser la bibliothèque')),
                  PopupMenuItem(value: 'settings', child: Text('Réglages')),
                ]),
            ],
          ),
'''
    # On mobile: one toolbar button + overflow. Desktop: five controls as before.
    beginning='''            title: Platform.isAndroid
              ? Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(radiusSm),
                    child: Image.asset('assets/icon.png', width: 27, height: 27)),
                  const SizedBox(width: 8),
                  const Flexible(child: Text('Anime Organizer', maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
                ])
              : Column(
'''
    # original starts with title: Column; remove that prefix then use modified body
    desktop_title=title.replace('            title: Column(\n','',1)
    result=beginning+desktop_title+'            actions: Platform.isAndroid ? [\n'
    # small has complete 'actions:' and close; splice cleanly
    result=result[:result.rfind('            actions: Platform.isAndroid ? [\n')]
    small_actions=small.replace('            actions: [','',1).rsplit('          ),\n',1)[0]
    desktop_actions=actions.replace('            actions: [','',1).rsplit('          ),\n',1)[0]
    result+='            actions: Platform.isAndroid ? [\n'+small_actions+'            ] : [\n'+desktop_actions+'          ),\n'
    # ensure no duplicate ] introduced from action fragments
    result=result.replace('            ],\n            ] : [','            ] : [')
    result=result.replace('            ],\n          ),\n          floatingActionButton:', '            ],\n          ),\n          floatingActionButton:')
    # desktop_actions includes closing "            ],\n", final has no extra closure
    if result.endswith('            ],\n          ),\n') and desktop_actions.rstrip().endswith('],'): pass
    else: raise SystemExit('V39: structure AppBar inattendue')
    return s[:start]+result+s[end:]

def pc(s):
    s=replace_one(s,"  List<Map<String, dynamic>> _remote = [];\n",'''  List<Map<String, dynamic>> _remote = [];
  RawDatagramSocket? _discovery;
  final Map<String, String> _found = {};
  bool _looking = false;
  String _pairedHost = '';

  Future<File> _pairStore() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'anime_pc_pairing.json'));
  }

  Future<void> _loadSavedPair() async {
    try {
      final f = await _pairStore();
      if (!await f.exists()) return;
      final value = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final host = '${value['host'] ?? ''}';
      final code = '${value['code'] ?? ''}';
      if (!RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(host) ||
          !RegExp(r'^[A-Z2-9]{12}$').hasMatch(code)) return;
      _pairedHost = host;
      _address.text = host;
      _code.text = code;
      if (mounted) setState(() => _message = 'Dernier PC associé : $host. Recherche sur le Wi-Fi…');
    } catch (_) {}
  }

  Future<void> _savePair(String host, String code) async {
    final file = await _pairStore();
    await file.writeAsString(jsonEncode({'host': host, 'code': code}), flush: true);
    _pairedHost = host;
  }

  Future<void> _startDiscovery() async {
    if (!Platform.isAndroid || _discovery != null) return;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8766,
          reuseAddress: true);
      _discovery = socket;
      if (mounted) setState(() { _looking = true; });
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = socket.receive()) != null) {
          try {
            final data = jsonDecode(utf8.decode(packet!.data)) as Map<String, dynamic>;
            if (data['service'] != 'anime-organizer-sync' || data['port'] != _port) continue;
            final host = packet!.address.address;
            if (host.startsWith('127.') || host.startsWith('169.254.')) continue;
            _found[host] = '${data['name'] ?? 'PC Anime Organizer'}';
            if (mounted) setState(() {
              if (_address.text.isEmpty || _address.text == _pairedHost) {
                _address.text = host;
              }
            });
            // Auto-reconnection only for a previously paired host and code.
            if (_pairedHost == host && _code.text.length == 12 && !_busy && _remote.isEmpty) {
              unawaited(_connect(auto: true));
            }
          } catch (_) {}
        }
      });
    } catch (e) {
      if (mounted) setState(() => _message =
        'Découverte Wi-Fi indisponible ($e). Utilise la connexion manuelle.');
    }
  }

  Future<void> _loadOrCreateServerToken() async {
    final file = await _pairStore();
    try {
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final saved = '${data['code'] ?? ''}';
        if (RegExp(r'^[A-Z2-9]{12}$').hasMatch(saved)) {
          _pairCode = saved;
          return;
        }
      }
    } catch (_) {}
    _pairCode = _newCode();
    await file.writeAsString(jsonEncode({'code': _pairCode}), flush: true);
  }
''','pc state')
    s=replace_one(s,"    if (Platform.isWindows) _findIp();\n",'''    if (Platform.isWindows) _findIp();
    if (Platform.isAndroid) {
      unawaited(_loadSavedPair().then((_) => _startDiscovery()));
    }
''','pc init')
    s=replace_one(s,"      final token = _newCode();\n",'''      await _loadOrCreateServerToken();
      final token = _pairCode;
''','persistent code')
    s=replace_one(s,"  Future<void> _connect() async {\n", "  Future<void> _connect({bool auto = false}) async {\n",'connect signature')
    s=replace_one(s,"      _message = '${_remote.length} séries reçues depuis le PC. Aucune vidéo transférée.';\n",'''      _message = '${_remote.length} séries reçues depuis le PC. Aucune vidéo transférée.';
      await _savePair(host, token);
''','save pair')
    s=replace_one(s,"      _message = 'Connexion impossible : $e. Vérifie le même Wi-Fi et le pare-feu Windows.';\n",'''      _message = 'Connexion impossible : $e. Vérifie le même Wi-Fi et le pare-feu Windows.';
''','connection error')
    s=replace_one(s,"    _server?.kill();\n", "    _discovery?.close();\n    _server?.kill();\n",'discovery dispose')
    s=replace_one(s,"        ] else ...[\n          TextField(controller: _address,\n",'''        ] else ...[
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.wifi_find),
                const SizedBox(width: 8),
                Expanded(child: Text(_found.isNotEmpty
                  ? '${_found.length} PC détecté(s) sur le Wi-Fi'
                  : _looking ? 'Recherche des PC sur le Wi-Fi…'
                      : 'Découverte Wi-Fi indisponible')),
                IconButton(tooltip: 'Relancer la recherche',
                  onPressed: () { _discovery?.close(); _discovery = null;
                    _found.clear(); unawaited(_startDiscovery()); },
                  icon: const Icon(Icons.refresh)),
              ]),
              for (final item in _found.entries)
                ListTile(dense: true, leading: const Icon(Icons.computer),
                  title: Text(item.value), subtitle: Text(item.key),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _address.text = item.key;
                    if (_code.text.length == 12) {
                      unawaited(_connect());
                    } else {
                      setState(() => _message = 'PC sélectionné : saisis une fois le code d’association.');
                    }
                  }),
              if (_found.isEmpty) const Text(
                'Démarre le serveur sur Windows. Le PC apparaîtra ici si le Wi-Fi autorise la découverte locale.'),
            ]))),
          const SizedBox(height: 12),
          ExpansionTile(title: const Text('Connexion manuelle / Tailscale'),
            initiallyExpanded: false, children: [
          TextField(controller: _address,
''','manual start')
    s=replace_one(s,"          FilledButton.icon(onPressed: _busy ? null : _connect,\n",'''          ]),
          TextField(controller: _code, textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Code d’association (12 caractères)'),
            maxLength: 12),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _busy ? null : () => _connect(),
''','manual end')
    s=replace_one(s,"'Connecte les deux appareils au même Wi-Fi ou à ton réseau privé Tailscale. Les vidéos restent sur le PC.'", "'Démarre le serveur sur Windows. Le PC devrait apparaître automatiquement sur le même Wi-Fi. Tailscale reste accessible en connexion manuelle.'",'instructions')
    return s

def server(s):
    s=replace_one(s,'import sys\n','import sys\nimport socket\n','socket import')
    s=replace_one(s,"if __name__ == '__main__':\n",'''def announce_server(port):
    """LAN-only UDP broadcast discovery; never send authentication tokens."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        packet = json.dumps({
            'service': 'anime-organizer-sync', 'port': port,
            'name': socket.gethostname()[:55], 'version': 1,
        }).encode('utf-8')
        while True:
            try:
                sock.sendto(packet, ('255.255.255.255', 8766))
            except OSError:
                pass
            time.sleep(2.5)
    except OSError:
        return


if __name__ == '__main__':
''','broadcast setup')
    s=replace_one(s,"    ThreadingHTTPServer(('0.0.0.0', args.port), handler_factory(Path(args.library), args.token)).serve_forever()\n",'''    threading.Thread(target=announce_server, args=(args.port,), daemon=True).start()
    ThreadingHTTPServer(('0.0.0.0', args.port), handler_factory(Path(args.library), args.token)).serve_forever()
''','broadcast start')
    return s

update('lib/screens/home_screen.dart',home)
update('lib/screens/pc_sync_screen.dart',pc)
update('tool/sync_server.py',server)
print('V39: patches ready')
