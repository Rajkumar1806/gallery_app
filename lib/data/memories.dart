import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

/// An auto-generated story such as "Two weeks in review – September 2026".
class Memory {
  Memory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.assets,
    required this.cover,
    required this.start,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<AssetEntity> assets;
  final AssetEntity cover;
  final DateTime start;
}

/// Groups the library into half-month windows ("Two weeks in review") and
/// adds an "On this day" memory when older photos share today's date.
List<Memory> buildMemories(
  List<AssetEntity> all, {
  required int Function(String id) faceScore,
  int minPhotos = 6,
}) {
  final monthFmt = DateFormat('MMMM yyyy');
  final windows = <DateTime, List<AssetEntity>>{};
  for (final a in all) {
    final d = a.createDateTime;
    final start = DateTime(d.year, d.month, d.day <= 14 ? 1 : 15);
    (windows[start] ??= []).add(a);
  }

  final memories = <Memory>[];

  // On this day
  final now = DateTime.now();
  final onThisDay = all
      .where((a) =>
          a.createDateTime.month == now.month &&
          a.createDateTime.day == now.day &&
          a.createDateTime.year < now.year)
      .toList();
  if (onThisDay.length >= 3) {
    final years = now.year - onThisDay.first.createDateTime.year;
    memories.add(Memory(
      id: 'otd-${now.month}-${now.day}',
      title: 'On this day',
      subtitle: years == 1 ? '1 year ago' : '$years years ago',
      assets: onThisDay,
      cover: _pickCover(onThisDay, faceScore),
      start: onThisDay.first.createDateTime,
    ));
  }

  final keys = windows.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final k in keys) {
    final list = windows[k]!;
    if (list.length < minPhotos) continue;
    memories.add(Memory(
      id: 'tw-${k.toIso8601String()}',
      title: 'Two weeks in review',
      subtitle: monthFmt.format(k),
      assets: list,
      cover: _pickCover(list, faceScore),
      start: k,
    ));
  }
  return memories;
}

/// Prefers a photo (not video) with people in it, otherwise the middle one.
AssetEntity _pickCover(List<AssetEntity> list, int Function(String) faceScore) {
  final photos = list.where((a) => a.type == AssetType.image).toList();
  if (photos.isEmpty) return list.first;
  AssetEntity? best;
  var bestScore = 0;
  for (final p in photos) {
    final s = faceScore(p.id);
    if (s > bestScore && s <= 4) {
      best = p;
      bestScore = s;
    }
  }
  return best ?? photos[photos.length ~/ 2];
}
