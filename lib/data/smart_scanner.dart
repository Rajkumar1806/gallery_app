import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_repository.dart';

/// What the on-device scan learned about one photo.
class SmartInfo {
  SmartInfo({
    required this.tags,
    required this.faces,
    this.fx = 0.5,
    this.fy = 0.4,
    this.lat,
    this.lng,
  });

  final List<String> tags;
  final int faces;

  /// Centre of the largest face, normalised 0..1 (used to crop avatars).
  final double fx, fy;
  final double? lat, lng;

  Map<String, dynamic> toJson() => {
        't': tags,
        'f': faces,
        'x': fx,
        'y': fy,
        if (lat != null) 'la': lat,
        if (lng != null) 'lo': lng,
      };

  factory SmartInfo.fromJson(Map<String, dynamic> j) => SmartInfo(
        tags: (j['t'] as List).cast<String>(),
        faces: j['f'] as int,
        fx: (j['x'] as num?)?.toDouble() ?? 0.5,
        fy: (j['y'] as num?)?.toDouble() ?? 0.4,
        lat: (j['la'] as num?)?.toDouble(),
        lng: (j['lo'] as num?)?.toDouble(),
      );
}

/// A cluster of photos taken near the same spot (~10 km).
class PlaceInfo {
  PlaceInfo({required this.key, required this.name, required this.assets});
  final String key;
  final String name;
  final List<AssetEntity> assets;
}

/// Smart-tag categories, built from ML Kit's on-device image labels.
const Map<String, List<String>> kTagRules = {
  'Food': [
    'food', 'cake', 'bread', 'fruit', 'vegetable', 'pizza', 'dessert',
    'cookie', 'cuisine', 'dish', 'meal', 'sushi', 'pasta', 'noodle', 'icing',
    'baked goods', 'fast food', 'juice', 'coffee', 'tea', 'cup', 'plate',
  ],
  'Buildings': [
    'building', 'skyscraper', 'tower', 'temple', 'church', 'mosque',
    'castle', 'bridge', 'monument', 'house', 'palace', 'shrine', 'statue',
    'architecture', 'stadium',
  ],
  'Nature': [
    'flower', 'plant', 'tree', 'sky', 'lake', 'sunset', 'beach', 'mountain',
    'waterfall', 'garden', 'forest', 'river', 'cloud', 'grass', 'leaf',
    'sea', 'rainbow', 'petal',
  ],
  'Animals': [
    'dog', 'cat', 'bird', 'pet', 'horse', 'butterfly', 'insect', 'fish',
    'cattle', 'duck', 'monkey', 'elephant',
  ],
  'Vehicles': [
    'car', 'bicycle', 'motorcycle', 'bus', 'vehicle', 'wheel', 'truck',
    'train', 'airplane', 'boat', 'tire',
  ],
  'Documents': [
    'paper', 'poster', 'menu', 'receipt', 'newspaper', 'document', 'text',
    'handwriting', 'whiteboard', 'screenshot', 'chart',
  ],
  'Celebrations': [
    'balloon', 'party', 'fireworks', 'christmas', 'candle', 'event',
    'wedding', 'festival', 'gift', 'bride',
  ],
  'Selfies': ['selfie'],
  'Babies': ['baby', 'toddler', 'child'],
};

const kTagIcons = {
  'Food': '🍰',
  'Buildings': '🏛',
  'Nature': '🌿',
  'Animals': '🐾',
  'Vehicles': '🛵',
  'Documents': '📄',
  'Celebrations': '🎉',
  'Selfies': '🤳',
  'Babies': '🍼',
};

/// Runs ML Kit image labelling + face detection on downscaled thumbnails,
/// entirely on-device, and caches the results.
class SmartScanner extends ChangeNotifier {
  SmartScanner(this.repo);

  final MediaRepository repo;

  /// Newest N photos scanned. Raise it if you want a deeper index.
  static const maxScan = 3000;
  static const _prefsKey = 'smart_index_v1';
  static const _placesKey = 'place_names_v1';

  final Map<String, SmartInfo> _index = {};
  final Map<String, String> _placeNames = {};
  List<PlaceInfo> places = const [];
  Map<String, List<AssetEntity>> tagged = const {};
  List<AssetEntity> withFaces = const [];

  bool running = false;
  int done = 0;
  int total = 0;
  bool _cancel = false;
  bool _restored = false;

  double get progress => total == 0 ? 1 : done / total;

  int faceCount(String id) => _index[id]?.faces ?? 0;
  SmartInfo? infoOf(String id) => _index[id];
  List<String> tagsOf(String id) => _index[id]?.tags ?? const [];

  String? placeNameOf(String id) {
    final info = _index[id];
    if (info?.lat == null) return null;
    return _placeNames[_placeKey(info!.lat!, info.lng!)];
  }

  Future<void> start() async {
    if (running) return;
    running = true;
    _cancel = false;

    final prefs = await SharedPreferences.getInstance();
    if (!_restored) {
      _restored = true;
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        m.forEach((k, v) => _index[k] = SmartInfo.fromJson(v as Map<String, dynamic>));
      }
      final rawPlaces = prefs.getString(_placesKey);
      if (rawPlaces != null) {
        _placeNames.addAll((jsonDecode(rawPlaces) as Map).cast<String, String>());
      }
    }
    _rebuild();

    final todo = repo.all
        .where((a) => a.type == AssetType.image)
        .take(maxScan)
        .where((a) => !_index.containsKey(a.id))
        .toList();
    total = todo.length;
    done = 0;
    notifyListeners();

    if (todo.isNotEmpty) {
      final labeler =
          ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.6));
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
      );
      final tmpDir = await getTemporaryDirectory();
      final tmp = File('${tmpDir.path}/scan_thumb.jpg');

      for (final asset in todo) {
        if (_cancel) break;
        try {
          _index[asset.id] = await _scanOne(asset, labeler, faceDetector, tmp);
        } catch (e) {
          debugPrint('scan failed for ${asset.id}: $e');
          _index[asset.id] = SmartInfo(tags: const [], faces: 0);
        }
        done++;
        if (done % 40 == 0 || done == total) {
          _rebuild();
          await prefs.setString(_prefsKey, jsonEncode(_index));
          notifyListeners();
        }
      }
      await labeler.close();
      await faceDetector.close();
      await prefs.setString(_prefsKey, jsonEncode(_index));
    }

    await _resolvePlaceNames(prefs);
    _rebuild();
    running = false;
    repo.invalidateMemories();
    notifyListeners();
  }

  Future<SmartInfo> _scanOne(
    AssetEntity asset,
    ImageLabeler labeler,
    FaceDetector faceDetector,
    File tmp,
  ) async {
    final bytes =
        await asset.thumbnailDataWithSize(ThumbnailSize(640, 640), quality: 85);
    final tags = <String>{};
    var faces = 0;
    double fx = 0.5, fy = 0.4;

    if (bytes != null) {
      await tmp.writeAsBytes(bytes, flush: true);
      final input = InputImage.fromFilePath(tmp.path);

      final labels = await labeler.processImage(input);
      for (final l in labels) {
        final name = l.label.toLowerCase();
        final words = name.split(RegExp(r'[\s-]+'));
        kTagRules.forEach((tag, rules) {
          if (rules.any((w) => name == w || words.contains(w))) tags.add(tag);
        });
      }

      final found = await faceDetector.processImage(input);
      faces = found.length;
      if (found.isNotEmpty) {
        final biggest = found.reduce((a, b) =>
            a.boundingBox.width * a.boundingBox.height >=
                    b.boundingBox.width * b.boundingBox.height
                ? a
                : b);
        final size = await _imageSize(bytes);
        if (size != null) {
          fx = (biggest.boundingBox.center.dx / size.width).clamp(0.0, 1.0);
          fy = (biggest.boundingBox.center.dy / size.height).clamp(0.0, 1.0);
        }
        // A single big face close to the camera is very likely a selfie.
        final rel = biggest.boundingBox.width / (size?.width ?? 640);
        if (faces == 1 && rel > 0.35) tags.add('Selfies');
      }
    }

    double? lat, lng;
    try {
      final ll = await asset.latlngAsync();
      final la = ll?.latitude, lo = ll?.longitude;
      if (la != null && lo != null && !(la == 0 && lo == 0)) {
        lat = la;
        lng = lo;
      }
    } catch (_) {}

    return SmartInfo(
        tags: tags.toList(), faces: faces, fx: fx, fy: fy, lat: lat, lng: lng);
  }

  static Future<ui.Size?> _imageSize(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final s = ui.Size(desc.width.toDouble(), desc.height.toDouble());
      desc.dispose();
      buffer.dispose();
      return s;
    } catch (_) {
      return null;
    }
  }

  static String _placeKey(double lat, double lng) =>
      '${(lat * 10).round()}:${(lng * 10).round()}';

  Future<void> _resolvePlaceNames(SharedPreferences prefs) async {
    final keys = <String, SmartInfo>{};
    for (final info in _index.values) {
      if (info.lat == null) continue;
      keys.putIfAbsent(_placeKey(info.lat!, info.lng!), () => info);
    }
    var changed = false;
    for (final e in keys.entries) {
      if (_placeNames.containsKey(e.key) || _cancel) continue;
      try {
        final marks = await placemarkFromCoordinates(e.value.lat!, e.value.lng!);
        if (marks.isNotEmpty) {
          final p = marks.first;
          // NB: do NOT use firstWhere(orElse: () => null) here – the list's
          // element type is non-nullable String, so returning null throws at
          // runtime as soon as no component is non-empty.
          String? name;
          for (final s in [
            p.subLocality,
            p.locality,
            p.subAdministrativeArea,
            p.administrativeArea,
          ]) {
            if (s != null && s.trim().isNotEmpty) {
              name = s;
              break;
            }
          }
          _placeNames[e.key] = name ?? 'Unknown place';
          changed = true;
        }
      } catch (_) {
        // Offline or geocoder unavailable – try again next launch.
      }
    }
    if (changed) await prefs.setString(_placesKey, jsonEncode(_placeNames));
  }

  void _rebuild() {
    final tagMap = <String, List<AssetEntity>>{};
    final faces = <AssetEntity>[];
    final placeMap = <String, List<AssetEntity>>{};

    for (final a in repo.all) {
      final info = _index[a.id];
      if (info == null) continue;
      for (final t in info.tags) {
        (tagMap[t] ??= []).add(a);
      }
      if (info.faces > 0) faces.add(a);
      if (info.lat != null) {
        (placeMap[_placeKey(info.lat!, info.lng!)] ??= []).add(a);
      }
    }

    // Merge clusters that resolved to the same place name.
    final named = <String, List<AssetEntity>>{};
    placeMap.forEach((key, list) {
      final name = _placeNames[key] ?? 'Locating…';
      (named[name] ??= []).addAll(list);
    });
    places = named.entries
        .map((e) => PlaceInfo(key: e.key, name: e.key, assets: e.value
          ..sort((a, b) => b.createDateTime.compareTo(a.createDateTime))))
        .toList()
      ..sort((a, b) => b.assets.length.compareTo(a.assets.length));

    tagged = Map.fromEntries(tagMap.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length)));
    withFaces = faces;
  }

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }
}
