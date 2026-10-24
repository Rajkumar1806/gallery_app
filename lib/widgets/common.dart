import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../data/gallery_scope.dart';
import '../screens/viewer_screen.dart';
import '../theme.dart';

/// Frosted-glass surface used for the search bar, nav bar and pills.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.blur = 22,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: GalleryColors.glass(b),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: GalleryColors.glassBorder(b), width: 0.8),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A thumbnail for one photo/video with video-duration and favourite badges.
class AssetThumb extends StatelessWidget {
  const AssetThumb(
    this.asset, {
    super.key,
    this.radius = 0,
    this.size = 300,
    this.alignment = Alignment.center,
    this.showBadges = true,
  });

  final AssetEntity asset;
  final double radius;
  final int size;
  final Alignment alignment;
  final bool showBadges;

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: ThumbnailSize.square(size),
      ),
      fit: BoxFit.cover,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.black12,
        child: const Icon(Icons.broken_image_outlined, color: Colors.black26),
      ),
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: child,
            ),
    );

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black.withOpacity(0.05)),
        image,
        if (showBadges && asset.type == AssetType.video)
          Positioned(
            right: 5,
            bottom: 4,
            child: Row(children: [
              const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 15,
                  shadows: [Shadow(blurRadius: 4)]),
              Text(formatDuration(asset.videoDuration),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 4)])),
            ]),
          ),
        if (showBadges && GalleryScope.of(context).isFavorite(asset))
          const Positioned(
            left: 5,
            bottom: 4,
            child: Icon(Icons.favorite, color: Colors.white, size: 14,
                shadows: [Shadow(blurRadius: 4)]),
          ),
      ],
    );
    if (radius > 0) {
      content = ClipRRect(borderRadius: BorderRadius.circular(radius), child: content);
    }
    return content;
  }
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Opens the full-screen viewer at [index] inside [assets].
void openViewer(BuildContext context, List<AssetEntity> assets, int index) {
  Navigator.of(context).push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => ViewerScreen(assets: assets, initialIndex: index),
    transitionsBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  ));
}

/// A header + grid pair inside a CustomScrollView.
class AssetGroup {
  AssetGroup(this.title, this.assets, {this.trailing});
  final String title;
  final String? trailing;
  final List<AssetEntity> assets;
}

/// Builds slivers for date-grouped grids. Tapping opens the viewer over the
/// flattened list so you can swipe across groups.
List<Widget> groupedGridSlivers(
  BuildContext context, {
  required List<AssetGroup> groups,
  required int columns,
  double spacing = 2,
  double headerHeight = 50,
  TextStyle? headerStyle,
  int thumbSize = 300,
}) {
  final flat = <AssetEntity>[for (final g in groups) ...g.assets];
  final style = headerStyle ??
      Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
  final slivers = <Widget>[];
  var offset = 0;
  for (final g in groups) {
    final base = offset;
    slivers.add(SliverToBoxAdapter(
      child: Container(
        height: headerHeight,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          Expanded(child: Text(g.title, style: style)),
          if (g.trailing != null)
            Text(g.trailing!,
                style: TextStyle(
                    fontSize: 12,
                    color: GalleryColors.subtle(Theme.of(context).brightness))),
        ]),
      ),
    ));
    slivers.add(SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => GestureDetector(
          onTap: () => openViewer(context, flat, base + i),
          child: AssetThumb(g.assets[i], size: thumbSize),
        ),
        childCount: g.assets.length,
      ),
    ));
    offset += g.assets.length;
  }
  return slivers;
}

/// 2×2 collage tile (People, Places, "Others").
class CollageTile extends StatelessWidget {
  const CollageTile({
    super.key,
    required this.assets,
    this.circle = false,
    this.alignments,
  });

  final List<AssetEntity> assets;
  final bool circle;
  final List<Alignment>? alignments;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: GalleryColors.glass(b),
          borderRadius: BorderRadius.circular(22),
        ),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 7,
          crossAxisSpacing: 7,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            for (var i = 0; i < 4; i++)
              i < assets.length
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(circle ? 100 : 14),
                      child: AssetThumb(
                        assets[i],
                        size: 160,
                        showBadges: false,
                        alignment: alignments != null && i < alignments!.length
                            ? alignments![i]
                            : Alignment.center,
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(circle ? 100 : 14),
                      ),
                    ),
          ],
        ),
      ),
    );
  }
}

/// Name + count caption under a tile, ColorOS style.
class TileCaption extends StatelessWidget {
  const TileCaption(this.title, this.count, {super.key});
  final String title;
  final String count;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(count,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: GalleryColors.subtle(b))),
        ],
      ),
    );
  }
}

/// "Smart tags            View All >" row.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onViewAll});
  final String title;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 12),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(foregroundColor: GalleryColors.subtle(b)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('View All'),
              Icon(Icons.chevron_right, size: 20),
            ]),
          ),
      ]),
    );
  }
}

/// Simple scaffold with gradient + back button for secondary pages.
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, required this.slivers, this.actions});
  final String title;
  final List<Widget> slivers;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: Text(title),
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              actions: actions,
            ),
            ...slivers,
            SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
          ],
        ),
      ),
    );
  }
}
