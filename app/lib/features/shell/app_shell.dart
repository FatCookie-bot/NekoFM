import 'package:flutter/material.dart';

import '../downloads/downloads_page.dart';
import '../library/library_page.dart';
import '../player/mini_player.dart';
import '../player/player_page.dart';
import '../settings/settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _libraryResetKey = 0;

  static const _destinations = <_ShellDestination>[
    _ShellDestination(label: 'Library', icon: Icons.album_outlined),
    _ShellDestination(label: 'Player', icon: Icons.play_circle_outline),
    _ShellDestination(label: 'Downloads', icon: Icons.download_outlined),
    _ShellDestination(label: 'Settings', icon: Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final wideLayout = MediaQuery.sizeOf(context).width >= 720;

    if (wideLayout) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectDestination,
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 24),
                child: _AppMark(),
              ),
              destinations: [
                for (final destination in _destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _ShellPage(
                destination: _destinations[_selectedIndex],
                page: _pageForIndex(_selectedIndex),
                showMiniPlayer: _selectedIndex != 1,
                onOpenPlayer: () => _selectDestination(1),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: _ShellPage(
        destination: _destinations[_selectedIndex],
        page: _pageForIndex(_selectedIndex),
        showMiniPlayer: _selectedIndex != 1,
        onOpenPlayer: () => _selectDestination(1),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectDestination,
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
      ),
    );
  }

  void _selectDestination(int index) {
    setState(() {
      if (index == 0 && _selectedIndex == 0) {
        _libraryResetKey += 1;
      }
      _selectedIndex = index;
    });
  }

  Widget _pageForIndex(int index) {
    return switch (index) {
      0 => LibraryPage(key: ValueKey(_libraryResetKey)),
      1 => const PlayerPage(),
      2 => const DownloadsPage(),
      3 => const SettingsPage(),
      _ => const LibraryPage(),
    };
  }
}

class _ShellDestination {
  const _ShellDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _ShellPage extends StatelessWidget {
  const _ShellPage({
    required this.destination,
    required this.page,
    required this.showMiniPlayer,
    required this.onOpenPlayer,
  });

  final _ShellDestination destination;
  final Widget page;
  final bool showMiniPlayer;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _AppMark(),
                const SizedBox(width: 12),
                Text(
                  destination.label,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(padding: const EdgeInsets.all(24), child: page),
              ),
            ),
            if (showMiniPlayer) ...[
              const SizedBox(height: 12),
              MiniPlayer(onOpenPlayer: onOpenPlayer),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'NekoFM',
      child: ExcludeSemantics(
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'N',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
