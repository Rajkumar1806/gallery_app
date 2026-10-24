import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';

import '../widgets/common.dart';

final _dayFmt = DateFormat('MMM d, yyyy');
final _dayFmtThisYear = DateFormat('EEE, MMM d');
final _monthFmt = DateFormat('MMMM yyyy');

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return _dayFmt.format(d);
}

String dayLabelLong(DateTime d) {
  final now = DateTime.now();
  final s = dayLabel(d);
  if (s == 'Today' || s == 'Yesterday') return s;
  return d.year == now.year ? _dayFmtThisYear.format(d) : _dayFmt.format(d);
}

/// Assumes [assets] is sorted newest first.
List<AssetGroup> groupByDay(List<AssetEntity> assets, {bool long = false}) {
  final out = <AssetGroup>[];
  DateTime? current;
  List<AssetEntity>? bucket;
  for (final a in assets) {
    final d = a.createDateTime;
    final key = DateTime(d.year, d.month, d.day);
    if (key != current) {
      current = key;
      bucket = [];
      out.add(AssetGroup(long ? dayLabelLong(d) : dayLabel(d), bucket));
    }
    bucket!.add(a);
  }
  return out;
}

List<AssetGroup> groupByMonth(List<AssetEntity> assets) {
  final out = <AssetGroup>[];
  DateTime? current;
  List<AssetEntity>? bucket;
  for (final a in assets) {
    final d = a.createDateTime;
    final key = DateTime(d.year, d.month);
    if (key != current) {
      current = key;
      bucket = [];
      out.add(AssetGroup(_monthFmt.format(d), bucket));
    }
    bucket!.add(a);
  }
  return [
    for (final g in out) AssetGroup(g.title, g.assets, trailing: '${g.assets.length} items'),
  ];
}

Map<int, List<AssetEntity>> groupByYear(List<AssetEntity> assets) {
  final out = <int, List<AssetEntity>>{};
  for (final a in assets) {
    (out[a.createDateTime.year] ??= []).add(a);
  }
  return out;
}

String countLabel(List<AssetEntity> assets) {
  final videos = assets.where((a) => a.type == AssetType.video).length;
  final photos = assets.length - videos;
  final parts = <String>[
    if (photos > 0) '$photos photo${photos == 1 ? '' : 's'}',
    if (videos > 0) '$videos video${videos == 1 ? '' : 's'}',
  ];
  return parts.isEmpty ? 'Empty' : parts.join(', ');
}
