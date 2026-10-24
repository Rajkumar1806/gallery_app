import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/gallery_scope.dart';
import '../data/media_repository.dart';
import '../data/smart_scanner.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'asset_grid_screen.dart';
import 'home_shell.dart';
import 'memories_screen.dart';

/// Alignment that centres a thumbnail on the detected face.
Alignment faceAlignment(SmartScanner s, AssetEntity a) {
  final info = s.infoOf(a.id);
  if (info == null || info.faces == 0) return Alignment.center;
  return Alignment(info.fx * 2 - 1, info.fy * 2 - 1);
}

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = GalleryScope.of(context);
    return ListenableBuilder(
      listenable: repo.scanner,
      builder: (context, _) => _build(context, repo, repo.scanner),
    );
  }

  Widget _build(BuildContext context, MediaRepository repo, SmartScanner s) {
    final width = MediaQuery.sizeOf(context).width;
    final peopleTileW = (width - 32 - 20) / 2.5;
    final memories = repo.memories;
    final tags = s.tagged.entries.toList();

    // Pick up to four distinct "faces" for the People tile.
    final people = <AssetEntity>[];
    for (final a in s.withFaces) {
      if ((s.infoOf(a.id)?.faces ?? 0) == 1) people.add(a);
      if (people.length == 4) break;
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: ShellInsets.top(context) - 12)),

        if (s.running && s.total > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Analyzing photos on this device… ${s.done}/${s.total}',
                    style: TextStyle(
                        fontSize: 12,
                        color: GalleryColors.subtle(Theme.of(context).brightness))),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: s.progress, minHeight: 3),
                ),
              ]),
            ),
          ),

        // ---------------------------------------------------- People & places
        const SliverToBoxAdapter(child: SectionHeader('People & places')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: peopleTileW,
                child: GestureDetector(
                  onTap: () => AssetGridScreen.open(context, 'People', s.withFaces),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CollageTile(
                      assets: people,
                      circle: true,
                      alignments: [for (final p in people) faceAlignment(s, p)],
                    ),
                    TileCaption('People', '${s.withFaces.length}'),
                  ]),
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: peopleTileW,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlacesScreen())),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CollageTile(assets: [for (final p in s.places.take(4)) p.assets.first]),
                    TileCaption('Places', '${s.places.length}'),
                  ]),
                ),
              ),
            ]),
          ),
        ),

        // -------------------------------------------------------- Smart tags
        SliverToBoxAdapter(
          child: SectionHeader('Smart tags',
              onViewAll: tags.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SmartTagsScreen()))),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 196,
            child: tags.isEmpty
                ? Center(
                    child: Text(
                        s.running ? 'Finding food, buildings, pets…' : 'No smart tags yet',
                        style: TextStyle(
                            color: GalleryColors.subtle(Theme.of(context).brightness))))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: tags.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, i) {
                      final t = tags[i];
                      return _TagTile(name: t.key, assets: t.value, size: 140);
                    },
                  ),
          ),
        ),

        // ---------------------------------------------------------- Memories
        SliverToBoxAdapter(
          child: SectionHeader('Memories',
              onViewAll: memories.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MemoriesScreen()))),
        ),
        if (memories.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('Memories appear once you have a few weeks of photos',
                    style: TextStyle(
                        color: GalleryColors.subtle(Theme.of(context).brightness))),
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: SizedBox(
              height: 240,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: memories.length.clamp(0, 10),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => SizedBox(
                  width: width - 56,
                  child: MemoryCard(memory: memories[i]),
                ),
              ),
            ),
          ),

        SliverToBoxAdapter(child: SizedBox(height: ShellInsets.bottom(context) + 24)),
      ],
    );
  }
}

class _TagTile extends StatelessWidget {
  const _TagTile({required this.name, required this.assets, required this.size});
  final String name;
  final List<AssetEntity> assets;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => AssetGridScreen.open(context, name, assets),
      child: SizedBox(
        width: size,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: size,
            height: size,
            child: AssetThumb(assets.first, radius: 20, showBadges: false),
          ),
          TileCaption(name, '${assets.length}'),
        ]),
      ),
    );
  }
}

class SmartTagsScreen extends StatelessWidget {
  const SmartTagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = GalleryScope.of(context).scanner;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final tags = s.tagged.entries.toList();
        return SubPage(
          title: 'Smart tags',
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 190,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => LayoutBuilder(
                    builder: (context, c) => _TagTile(
                        name: tags[i].key, assets: tags[i].value, size: c.maxWidth),
                  ),
                  childCount: tags.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = GalleryScope.of(context).scanner;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => SubPage(
        title: 'Places',
        slivers: [
          if (s.places.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No places yet. Photos need location info (turn on '
                    '"Save location" in your camera settings).',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final p = s.places[i];
                    return GestureDetector(
                      onTap: () => AssetGridScreen.open(context, p.name, p.assets),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: AssetThumb(p.assets.first, radius: 20, showBadges: false),
                        ),
                        TileCaption(p.name, '${p.assets.length}'),
                      ]),
                    );
                  },
                  childCount: s.places.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
