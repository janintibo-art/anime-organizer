from pathlib import Path
p = Path('windows/runner/flutter_window.cpp')
if not p.exists():
    raise SystemExit('Le runner Windows manque : Flutter create doit passer avant ce correctif.')
s = p.read_text(encoding='utf-8')
include = '#include "desktop_multi_window/desktop_multi_window_plugin.h"'
if include not in s:
    marker = '#include "flutter/generated_plugin_registrant.h"'
    if marker not in s: raise SystemExit('Point C++ include introuvable, pas de modification.')
    s = s.replace(marker, marker + '\n' + include, 1)
registration = '''  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    RegisterPlugins(flutter_view_controller->engine());
  });
'''
if 'DesktopMultiWindowSetWindowCreatedCallback(' not in s:
    marker = '  RegisterPlugins(flutter_controller_->engine());'
    if marker not in s: raise SystemExit('Point C++ registration introuvable, pas de modification.')
    s = s.replace(marker, marker + '\n' + registration.rstrip(), 1)
p.write_text(s, encoding='utf-8')
print('V50 : enregistrement des plugins secondaires Windows OK')
