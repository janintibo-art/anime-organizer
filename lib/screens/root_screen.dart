import 'package:flutter/material.dart';

import '../main.dart';
import 'discover_screen.dart';
import 'home_screen.dart';

/// Les deux onglets de l'application : ce que tu possèdes, et le reste.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  // Les deux écrans restent en vie : changer d'onglet ne relance pas
  // le catalogue ni le défilement de la bibliothèque.
  final List<Widget> _pages = const [HomeScreen(), DiscoverScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Palette.line)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: Palette.ink,
          selectedItemColor: Palette.shu,
          unselectedItemColor: Palette.muted,
          selectedFontSize: 11.5,
          unselectedFontSize: 11.5,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.video_library_outlined),
              activeIcon: Icon(Icons.video_library),
              label: 'Bibliothèque',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: 'Découvrir',
            ),
          ],
        ),
      ),
    );
  }
}
