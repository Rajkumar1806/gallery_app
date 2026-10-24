import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'album_info.dart';
import 'memories.dart';
import 'smart_scanner.dart';

/// Virtual collections shown under "Media types".
enum MediaType { videos, gifs, screenshots, favorites, panoramas, recent }

extension MediaTypeLabel on MediaType {
  String get label => switch (this) {
        MediaType.videos => 'Videos',
        MediaType.gifs => 'GIF',
        MediaType.screenshots => 'Screenshots',
        MediaType.favorites => 'Favorites',
        MediaType.panoramas => 'Panoramas',
        MediaType.recent => 'Recently added',
      };
}

/// Single source of truth for everything the UI shows.
class MediaRepository extends ChangeNotifier {
  MediaRepository() {
    scanner = SmartScanner(this);
  }

  late final SmartScanner scanner;

  bool loading = false;
  bool loaded = false;
  List<AssetEntity> all = const [];
  List<AlbumInfo> albums = const [];

  /// asset id -> album name (used by search).
  final Map<String, String> _albumOf = {};
  Set<String> _favorites = {};
  List<Memory>? _memories;
  Timer? _reloadDebounce;
  bool _listening = false;

  // ---------------------------------------------------------------- loading

  Future<void> load() async {
    if (loading) return;
    loading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _favorites = (prefs.getStringList('favorites') ?? const []).toSet();

    final filter = FilterOptionGroup(
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    );
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
      filterOption: filter,
    );

    final allAssets = <AssetEntity>[];
    final albumList = <AlbumInfo>[];
    _albumOf.clear();

    for (final path in paths) {
      final assets = await _readAll(path);
      if (path.isAll) {
        allAssets.addAll(assets);
      } else if (assets.isNotEmpty) {
        albumList.add(AlbumInfo(id: path.id, name: path.name, assets: assets));
        for (final a in assets) {
          _albumOf[a.id] = path.name;
        }
      }
    }

    // Biggest albums first, but keep the camera roll on top like ColorOS.
    albumList.sort((a, b) {
      final ac = _isCamera(a.name), bc = _isCamera(b.name);
      if (ac != bc) return ac ? -1 : 1;
      return b.count.compareTo(a.count);
    });

    all = allAssets;
    albums = albumList;
    _memories = null;
    loading = false;
    loaded = true;
    notifyListeners();

    _listenForChanges();
    unawaited(scanner.start());
  }

  Future<List<AssetEntity>> _readAll(AssetPathEntity path) async {
    final total = await path.assetCountAsync;
    const page = 1000;
    final out = <AssetEntity>[];
    for (var start = 0; start < total; start += page) {
      final end = (start + page).clamp(0, total);
      out.addAll(await path.getAssetListRange(start: start, end: end));
    }
    return out;
  }

  void _listenForChanges() {
    if (_listening) return;
    _listening = true;
    PhotoManager.addChangeCallback(_onMediaChanged);
    PhotoManager.startChangeNotify();
  }

  void _onMediaChanged(MethodCall _) {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(seconds: 1), () {
      loading = false;
      load();
    });
  }

  static bool _isCamera(String name) {
    final n = name.toLowerCase();
    return n == 'camera' || n == 'dcim';
  }

  // ------------------------------------------------------------- favorites

  bool isFavorite(AssetEntity a) => _favorites.contains(a.id);

  Future<void> toggleFavorite(AssetEntity a) async {
    if (!_favorites.remove(a.id)) _favorites.add(a.id);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', _favorites.toList());
  }

  // ---------------------------------------------------------------- delete

  /// Deletes from the device. Android 11+ shows the system confirmation.
  Future<bool> delete(List<AssetEntity> items) async {
    final ids = items.map((e) => e.id).toList();
    final deleted = (await PhotoManager.editor.deleteWithIds(ids)).toSet();
    if (deleted.isEmpty) return false;
    all = all.where((a) => !deleted.contains(a.id)).toList();
    albums = [
      for (final al in albums)
        AlbumInfo(
          id: al.id,
          name: al.name,
          assets: al.assets.where((a) => !deleted.contains(a.id)).toList(),
        ),
    ].where((al) => al.count > 0).toList();
    _favorites.removeAll(deleted);
    _memories = null;
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------ media types

  String? albumNameOf(AssetEntity a) => _albumOf[a.id];

  static bool isGif(AssetEntity a) =>
      (a.mimeType?.toLowerCase() == 'image/gif') ||
      (a.title?.toLowerCase().endsWith('.gif') ?? false);

  bool _isScreenshot(AssetEntity a) {
    final album = _albumOf[a.id]?.toLowerCase() ?? '';
    final title = a.title?.toLowerCase() ?? '';
    return album.contains('screenshot') || title.startsWith('screenshot');
  }

  static bool _isPanorama(AssetEntity a) {
    if (a.type != AssetType.image || a.width == 0 || a.height == 0) return false;
    final r = a.width / a.height;
    return r >= 2.2 || (r <= 1 / 2.2 && a.height > 4000);
  }

  List<AssetEntity> mediaType(MediaType t) => switch (t) {
        MediaType.videos => all.where((a) => a.type == AssetType.video).toList(),
        MediaType.gifs => all.where(isGif).toList(),
        MediaType.screenshots => all.where(_isScreenshot).toList(),
        MediaType.favorites => all.where(isFavorite).toList(),
        MediaType.panoramas => all.where(_isPanorama).toList(),
        MediaType.recent => all
            .where((a) => DateTime.now().difference(a.createDateTime).inDays <= 30)
            .toList(),
      };

  // -------------------------------------------------------------- memories

  List<Memory> get memories =>
      _memories ??= buildMemories(all, faceScore: scanner.faceCount);

  void invalidateMemories() {
    _memories = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- search

  static final _monthFmt = DateFormat('MMMM yyyy');
  static final _dayFmt = DateFormat('d MMMM yyyy');
  static final _shortMonth = DateFormat('MMM');
  static final _weekday = DateFormat('EEEE');

  /// Matches file names, album names, dates ("sep 2024", "2025", "monday"),
  /// place names and smart tags.
  List<AssetEntity> search(String raw) {
    final terms = raw.toLowerCase().trim().split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    if (terms.isEmpty) return const [];

    return all.where((a) {
      final d = a.createDateTime;
      final haystack = StringBuffer()
        ..write(a.title ?? '')
        ..write(' ')
        ..write(_albumOf[a.id] ?? '')
        ..write(' ')
        ..write(_monthFmt.format(d))
        ..write(' ')
        ..write(_dayFmt.format(d))
        ..write(' ')
        ..write(_shortMonth.format(d))
        ..write(' ')
        ..write(_weekday.format(d))
        ..write(' ')
        ..write(a.type == AssetType.video ? 'video videos' : 'photo photos image')
        ..write(' ')
        ..write(scanner.placeNameOf(a.id) ?? '')
        ..write(' ')
        ..write(scanner.tagsOf(a.id).join(' '))
        ..write(isFavorite(a) ? ' favorite favourites' : '');
      final h = haystack.toString().toLowerCase();
      return terms.every(h.contains);
    }).toList();
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    if (_listening) {
      PhotoManager.removeChangeCallback(_onMediaChanged);
      PhotoManager.stopChangeNotify();
    }
    scanner.dispose();
    super.dispose();
  }
}
