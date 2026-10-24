import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../data/gallery_scope.dart';
import '../data/grouping.dart';
import '../data/memories.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Big rounded card: cover photo with "Two weeks in review / September 2026".
class MemoryCard extends StatelessWidget {
  const MemoryCard({super.key, required this.memory, this.titleSize = 28});
  final Memory memory;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MemoryScreen(memory: memory))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(fit: StackFit.expand, children: [
          AssetThumb(memory.cover, size: 700, showBadges: false),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x99000000)],
                stops: [0.55, 1],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 18,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(memory.title,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      shadows: const [Shadow(blurRadius: 8, color: Colors.black38)])),
              const SizedBox(height: 2),
              Text(memory.subtitle,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "View All" list of memories, styled like the reference screenshot.
class MemoriesScreen extends StatelessWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final memories = GalleryScope.of(context).memories;
    return SubPage(
      title: 'Memories',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: memories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) => SizedBox(
              height: 400,
              child: MemoryCard(memory: memories[i], titleSize: 32),
            ),
          ),
        ),
      ],
    );
  }
}

class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key, required this.memory});
  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Scaffold(
      body: GradientBackground(
        child: CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 420,
            pinned: true,
            stretch: true,
            foregroundColor: Colors.white,
            backgroundColor: Colors.black26,
            actions: [
              IconButton(
                tooltip: 'Play',
                icon: const Icon(Icons.play_circle_outline),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => SlideshowScreen(assets: memory.assets))),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 16),
              title: Text(memory.subtitle),
              background: Stack(fit: StackFit.expand, children: [
                AssetThumb(memory.cover, size: 900, showBadges: false),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x55000000), Colors.transparent, Color(0x99000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  bottom: 52,
                  child: Text(memory.title,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(countLabel(memory.assets),
                  style: TextStyle(color: GalleryColors.subtle(b))),
            ),
          ),
          ...groupedGridSlivers(context,
              groups: groupByDay(memory.assets, long: true), columns: 3, spacing: 3),
          SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
        ]),
      ),
    );
  }
}

/// Auto-advancing slideshow with a gentle Ken Burns zoom.
class SlideshowScreen extends StatefulWidget {
  const SlideshowScreen({super.key, required this.assets});
  final List<AssetEntity> assets;

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen> {
  late final List<AssetEntity> _photos =
      widget.assets.where((a) => a.type == AssetType.image).toList().reversed.toList();
  int _index = 0;
  Timer? _timer;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_paused || _photos.isEmpty) return;
      setState(() => _index = (_index + 1) % _photos.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_photos.isEmpty) {
      return const Scaffold(body: Center(child: Text('No photos to play')));
    }
    final asset = _photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _paused = !_paused),
        child: Stack(fit: StackFit.expand, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(asset.id),
              tween: Tween(begin: 1.0, end: 1.12),
              duration: const Duration(seconds: 5),
              builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
              child: Image(
                image: AssetEntityImageProvider(asset,
                    isOriginal: false, thumbnailSize: ThumbnailSize.square(1600)),
                fit: BoxFit.contain,
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                color: Colors.white,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          if (_paused)
            const Center(
                child: Icon(Icons.pause_circle_filled, color: Colors.white70, size: 72)),
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
            child: LinearProgressIndicator(
              value: (_index + 1) / _photos.length,
              backgroundColor: Colors.white24,
              color: Colors.white,
              minHeight: 2,
            ),
          ),
        ]),
      ),
    );
  }
}
