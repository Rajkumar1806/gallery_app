import 'package:flutter/material.dart';

import '../data/gallery_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'albums_screen.dart';
import 'explore_screen.dart';
import 'photos_screen.dart';
import 'search_screen.dart';

/// Bottom-tab shell: Photos / Albums / Explore, with a floating glass search
/// bar over the Photos tab and a floating glass tab bar at the bottom.
///
/// This file was missing from the project: only a small demo `HomeShell`
/// (3-column `GridView` + `CircularProgressIndicator`) existed, and the
/// `ShellInsets` helper used by `photos_screen.dart`, `albums_screen.dart` and
/// `explore_screen.dart` was never defined anywhere.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _pages = <Widget>[
    PhotosScreen(),
    AlbumsScreen(),
    ExploreScreen(),
  ];

  static const _items = <(IconData, IconData, String)>[
    (Icons.photo_library_outlined, Icons.photo_library, 'Photos'),
    (Icons.photo_album_outlined, Icons.photo_album, 'Albums'),
    (Icons.explore_outlined, Icons.explore, 'Explore'),
  ];

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: GradientBackground(
        child: Stack(
          children: [
            // Keep every tab alive so scroll positions survive a tab switch.
            IndexedStack(index: _tab, children: _pages),

            // Floating search bar (only on the Photos tab).
            if (_tab == 0)
              Positioned(
                left: 16,
                right: 16,
                top: MediaQuery.paddingOf(context).top + 4,
                child: Glass(
                  radius: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: InkWell(
                    onTap: _openSearch,
                    borderRadius: BorderRadius.circular(26),
                    child: SizedBox(
                      height: 46,
                      child: Row(
                        children: [
                          Icon(Icons.search,
                              color: GalleryColors.subtle(b), size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Search photos, places, things…',
                            style: TextStyle(
                              fontSize: 15,
                              color: GalleryColors.subtle(b),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Floating tab bar.
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 12,
              child: Center(
                child: Glass(
                  radius: 30,
                  padding: const EdgeInsets.all(5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        _TabButton(
                          icon: i == _tab ? _items[i].$2 : _items[i].$1,
                          label: _items[i].$3,
                          selected: i == _tab,
                          onTap: () => setState(() => _tab = i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final fg = selected
        ? Theme.of(context).colorScheme.primary
        : GalleryColors.subtle(b);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (b == Brightness.light
                  ? Colors.black.withOpacity(0.06)
                  : Colors.white.withOpacity(0.12))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: fg),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Space the screens have to reserve so their content is not hidden behind the
/// floating search bar / tab bar.
class ShellInsets {
  const ShellInsets._();

  /// Height of the floating glass tab bar (incl. its padding).
  static const double navBar = 56;

  /// Height of the floating glass search bar.
  static const double searchBar = 54;

  /// Gap the screens leave above/below the floating widgets.
  static const double gap = 12;

  /// Top inset: status bar + search bar.
  /// `photos_screen.dart` uses `ShellInsets.top(context) - 40`, so keep this
  /// generous enough that the value stays positive.
  static double top(BuildContext context) =>
      MediaQuery.paddingOf(context).top + searchBar + gap;

  /// Bottom inset: navigation bar + tab bar.
  static double bottom(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + navBar + gap;
}
