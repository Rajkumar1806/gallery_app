import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/gallery_scope.dart';
import '../data/grouping.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_shell.dart';

/// Zoom levels, from densest to largest.
/// NOTE: declaration order matters – pinch gestures step through
/// `Zoom.values[index ± 1]`, so it must match `_ZoomSwitcher._order`.
enum Zoom { years, months, days, all }

extension on Zoom {
  String get label => switch (this) {
        Zoom.years => 'Years',
        Zoom.months => 'Months',
        Zoom.days => 'Days',
        Zoom.all => 'All',
      };
  int get columns => switch (this) {
        Zoom.years => 1,
        Zoom.months => 6,
        Zoom.all => 4,
        Zoom.days => 3,
      };
  double get spacing => switch (this) {
        Zoom.months => 1.5,
        Zoom.days => 3,
        _ => 2,
      };
}

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  static const _headerHeight = 50.0;
  Zoom _zoom = Zoom.all;
  final _scroll = ScrollController();

  // Pinch tracking (Listener doesn't fight the scroll gesture).
  final Map<int, Offset> _pointers = {};
  double? _startSpan;
  bool _pinchHandled = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setZoom(Zoom z, {int? jumpToGroup}) {
    if (z == _zoom) return;
    final ratio = _scroll.hasClients && _scroll.position.maxScrollExtent > 0
        ? _scroll.offset / _scroll.position.maxScrollExtent
        : 0.0;
    setState(() => _zoom = z);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      final target = jumpToGroup != null ? _offsetOfGroup(jumpToGroup) : ratio * max;
      _scroll.jumpTo(target.clamp(0.0, max));
    });
  }

  /// Offset of group [index] in the months grid (fixed header heights make
  /// this exact without measuring).
  double _offsetOfGroup(int index) {
    final repo = GalleryScope.of(context, listen: false);
    final groups = groupByMonth(repo.all);
    final width = MediaQuery.sizeOf(context).width;
    const z = Zoom.months;
    final cell = (width - z.spacing * (z.columns - 1)) / z.columns;
    var y = 0.0;
    for (var i = 0; i < index && i < groups.length; i++) {
      final rows = (groups[i].assets.length / z.columns).ceil();
      y += _headerHeight + rows * cell + (rows - 1) * z.spacing;
    }
    // Spacer above the first header is (top - 40); keep the header visible
    // just below the floating search bar.
    return math.max(0, y - 40);
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _startSpan = _span();
      _pinchHandled = false;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length != 2 || _startSpan == null || _pinchHandled) return;
    final scale = _span() / _startSpan!;
    final idx = _zoom.index;
    if (scale > 1.35 && idx < Zoom.values.length - 1) {
      _pinchHandled = true;
      _setZoom(Zoom.values[idx + 1]);
    } else if (scale < 0.72 && idx > 0) {
      _pinchHandled = true;
      _setZoom(Zoom.values[idx - 1]);
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _startSpan = null;
  }

  double _span() {
    final p = _pointers.values.toList();
    return math.max(1, (p[0] - p[1]).distance);
  }

  @override
  Widget build(BuildContext context) {
    final repo = GalleryScope.of(context);
    final top = ShellInsets.top(context);
    final bottom = ShellInsets.bottom(context);

    if (repo.all.isEmpty) {
      return const Center(child: Text('No photos or videos yet'));
    }

    final slivers = switch (_zoom) {
      Zoom.years => [_yearsSliver(repo.all)],
      Zoom.months => groupedGridSlivers(context,
          groups: groupByMonth(repo.all),
          columns: _zoom.columns,
          spacing: _zoom.spacing,
          headerHeight: _headerHeight,
          thumbSize: 160),
      Zoom.all => groupedGridSlivers(context,
          groups: groupByDay(repo.all),
          columns: _zoom.columns,
          spacing: _zoom.spacing,
          headerHeight: _headerHeight),
      Zoom.days => groupedGridSlivers(context,
          groups: groupByDay(repo.all, long: true),
          columns: _zoom.columns,
          spacing: _zoom.spacing,
          headerHeight: _headerHeight,
          thumbSize: 400),
    };

    return Stack(
      children: [
        Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: RefreshIndicator(
            edgeOffset: top,
            onRefresh: repo.load,
            child: Scrollbar(
              controller: _scroll,
              interactive: true,
              thickness: 6,
              radius: const Radius.circular(3),
              child: CustomScrollView(
                key: ValueKey(_zoom),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: top - 40)),
                  ...slivers,
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 24, 16, bottom + 80),
                      child: Center(
                        child: Text(countLabel(repo.all),
                            style: TextStyle(
                                color: GalleryColors.subtle(
                                    Theme.of(context).brightness))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: bottom + 12,
          child: Center(child: _ZoomSwitcher(value: _zoom, onChanged: _setZoom)),
        ),
      ],
    );
  }

  Widget _yearsSliver(List<AssetEntity> all) {
    final years = groupByYear(all).entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final months = groupByMonth(all);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 40, 12, 0),
      sliver: SliverList.separated(
        itemCount: years.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, i) {
          final year = years[i];
          final preview = year.value.length <= 8
              ? year.value
              : List.generate(8, (k) => year.value[(k * year.value.length) ~/ 8]);
          return GestureDetector(
            onTap: () {
              final first = months.indexWhere(
                  (g) => g.assets.first.createDateTime.year == year.key);
              _setZoom(Zoom.months, jumpToGroup: math.max(0, first));
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 220,
                child: Stack(fit: StackFit.expand, children: [
                  Row(children: [
                    Expanded(flex: 2, child: AssetThumb(preview.first, size: 500, showBadges: false)),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Column(children: [
                        for (var k = 1; k < math.min(3, preview.length); k++) ...[
                          if (k > 1) const SizedBox(height: 2),
                          Expanded(child: AssetThumb(preview[k], showBadges: false)),
                        ],
                      ]),
                    ),
                  ]),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                        stops: [0.5, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    bottom: 14,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${year.key}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w600)),
                      Text(countLabel(year.value),
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ZoomSwitcher extends StatelessWidget {
  const _ZoomSwitcher({required this.value, required this.onChanged});
  final Zoom value;
  final ValueChanged<Zoom> onChanged;

  static const _order = [Zoom.years, Zoom.months, Zoom.days, Zoom.all];

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Glass(
      radius: 30,
      padding: const EdgeInsets.all(5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final z in _order)
            GestureDetector(
              onTap: () => onChanged(z),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: z == value
                      ? (b == Brightness.light
                          ? Colors.black.withOpacity(0.07)
                          : Colors.white.withOpacity(0.14))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(z.label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: z == value ? FontWeight.w600 : FontWeight.w400,
                        color: z == value ? null : GalleryColors.subtle(b))),
              ),
            ),
        ],
      ),
    );
  }
}
