import 'package:flutter/material.dart';

import '../data/album_info.dart';
import '../data/gallery_scope.dart';
import '../data/media_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'asset_grid_screen.dart';
import 'home_shell.dart';

class AlbumsScreen extends StatelessWidget {
  const AlbumsScreen({super.key});

  /// Albums with fewer items than this are folded into "Others"
  /// (as long as there are more than [_maxMain] albums).
  static const _maxMain = 8;
  static const _smallAlbum = 12;

  @override
  Widget build(BuildContext context) {
    final repo = GalleryScope.of(context);
    final b = Theme.of(context).brightness;

    final albums = repo.albums;
    final List<AlbumInfo> main;
    final List<AlbumInfo> others;
    if (albums.length <= _maxMain + 1) {
      main = albums;
      others = const [];
    } else {
      main = [
        for (var i = 0; i < albums.length; i++)
          if ((i < _maxMain && albums[i].count >= _smallAlbum) || i < 3) albums[i],
      ];
      others = albums.where((a) => !main.contains(a)).toList();
    }

    final types = [
      for (final t in MediaType.values)
        (type: t, items: repo.mediaType(t)),
    ].where((e) => e.items.isNotEmpty || e.type == MediaType.favorites).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: ShellInsets.top(context))),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 14,
              mainAxisSpacing: 10,
              childAspectRatio: 0.66,
            ),
            delegate: SliverChildListDelegate([
              for (final album in main)
                _AlbumTile(
                  title: album.name,
                  count: '${album.count}',
                  cover: AspectRatio(
                    aspectRatio: 1,
                    child: AssetThumb(album.cover!, radius: 18, showBadges: false),
                  ),
                  onTap: () => AssetGridScreen.open(context, album.name, album.assets),
                ),
              if (others.isNotEmpty)
                _AlbumTile(
                  title: 'Others',
                  count: others.map((a) => a.name).join(', '),
                  cover: CollageTile(assets: [for (final a in others.take(4)) a.cover!]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _OtherAlbumsScreen(albums: others))),
                ),
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: SectionHeader('Media types')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: GalleryColors.glass(b),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(children: [
                for (final e in types)
                  ListTile(
                    leading: Icon(_iconFor(e.type)),
                    title: Text(e.type.label, style: const TextStyle(fontSize: 17)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${e.items.length}',
                          style: TextStyle(color: GalleryColors.subtle(b), fontSize: 15)),
                      Icon(Icons.chevron_right, color: GalleryColors.subtle(b)),
                    ]),
                    onTap: () => AssetGridScreen.open(context, e.type.label, e.items),
                  ),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: ShellInsets.bottom(context) + 24)),
      ],
    );
  }

  static IconData _iconFor(MediaType t) => switch (t) {
        MediaType.videos => Icons.videocam_outlined,
        MediaType.gifs => Icons.gif_box_outlined,
        MediaType.screenshots => Icons.screenshot_outlined,
        MediaType.favorites => Icons.favorite_border,
        MediaType.panoramas => Icons.panorama_outlined,
        MediaType.recent => Icons.schedule,
      };
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.title,
    required this.count,
    required this.cover,
    required this.onTap,
  });

  final String title;
  final String count;
  final Widget cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [cover, TileCaption(title, count)],
      ),
    );
  }
}

class _OtherAlbumsScreen extends StatelessWidget {
  const _OtherAlbumsScreen({required this.albums});
  final List<AlbumInfo> albums;

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: 'Others',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 14,
              mainAxisSpacing: 10,
              childAspectRatio: 0.66,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final album = albums[i];
                return _AlbumTile(
                  title: album.name,
                  count: '${album.count}',
                  cover: AspectRatio(
                    aspectRatio: 1,
                    child: AssetThumb(album.cover!, radius: 18, showBadges: false),
                  ),
                  onTap: () => AssetGridScreen.open(context, album.name, album.assets),
                );
              },
              childCount: albums.length,
            ),
          ),
        ),
      ],
    );
  }
}
