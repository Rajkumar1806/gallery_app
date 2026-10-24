import 'package:photo_manager/photo_manager.dart';

/// One album / folder on the device.
///
/// This class was referenced by `media_repository.dart`, `albums_screen.dart`
/// and `search_screen.dart` but was never present in the project, which is one
/// of the reasons the app could not compile.
class AlbumInfo {
  const AlbumInfo({
    required this.id,
    required this.name,
    required this.assets,
  });

  final String id;
  final String name;

  /// Newest first (the repository sorts by `createDate` descending).
  final List<AssetEntity> assets;

  int get count => assets.length;

  /// Cover image, or `null` for an empty album. Callers use `album.cover!`
  /// after filtering out empty albums, so this is non-null in practice.
  AssetEntity? get cover => assets.isEmpty ? null : assets.first;

  @override
  bool operator ==(Object other) => other is AlbumInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AlbumInfo($name, $count)';
}
