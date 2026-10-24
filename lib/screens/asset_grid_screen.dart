import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/grouping.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Generic date-grouped grid for an album, media type, tag, place, etc.
class AssetGridScreen extends StatelessWidget {
  const AssetGridScreen({
    super.key,
    required this.title,
    required this.assets,
    this.emptyText = 'Nothing here yet',
  });

  final String title;
  final List<AssetEntity> assets;
  final String emptyText;

  static void open(BuildContext context, String title, List<AssetEntity> assets) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AssetGridScreen(title: title, assets: assets),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return SubPage(
      title: title,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(countLabel(assets),
                style: TextStyle(color: GalleryColors.subtle(b))),
          ),
        ),
        if (assets.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(emptyText)),
          )
        else
          ...groupedGridSlivers(context, groups: groupByDay(assets), columns: 4),
      ],
    );
  }
}
