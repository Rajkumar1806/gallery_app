import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../data/gallery_scope.dart';
import '../widgets/common.dart';

/// Full-screen swipe viewer with pinch-zoom, video playback, share,
/// favourite, info and delete.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.assets, required this.initialIndex});

  final List<AssetEntity> assets;
  final int initialIndex;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final List<AssetEntity> _assets = List.of(widget.assets);
  late int _index = widget.initialIndex;
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  bool _chrome = true;

  AssetEntity get _current => _assets[_index];

  @override
  void dispose() {
    _page.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    SystemChrome.setEnabledSystemUIMode(
        _chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  Future<void> _share() async {
    final file = await _current.file;
    if (file == null) return;
    await Share.shareXFiles([XFile(file.path, mimeType: _current.mimeType)]);
  }

  Future<void> _delete() async {
    final repo = GalleryScope.of(context, listen: false);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                'Delete this ${_current.type == AssetType.video ? 'video' : 'photo'} from your device?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ),
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final deleted = await repo.delete([_current]);
    if (!deleted || !mounted) return;
    setState(() {
      _assets.removeAt(_index);
      if (_index >= _assets.length) _index = _assets.length - 1;
    });
    if (_assets.isEmpty) Navigator.of(context).pop();
  }

  Future<void> _showInfo() async {
    final repo = GalleryScope.of(context, listen: false);
    final a = _current;
    final file = await a.file;
    final size = file != null ? await file.length() : null;
    if (!mounted) return;

    final rows = <(IconData, String, String)>[
      (Icons.insert_drive_file_outlined, 'Name', a.title ?? '—'),
      (Icons.event_outlined, 'Date', DateFormat('EEE, d MMM yyyy · h:mm a').format(a.createDateTime)),
      (Icons.photo_size_select_large, 'Resolution', '${a.width} × ${a.height}'),
      if (size != null) (Icons.sd_storage_outlined, 'Size', _bytes(size)),
      if (a.type == AssetType.video)
        (Icons.timer_outlined, 'Duration', formatDuration(a.videoDuration)),
      if (repo.albumNameOf(a) != null)
        (Icons.photo_album_outlined, 'Album', repo.albumNameOf(a)!),
      if (repo.scanner.placeNameOf(a.id) != null)
        (Icons.place_outlined, 'Place', repo.scanner.placeNameOf(a.id)!),
      if (repo.scanner.tagsOf(a.id).isNotEmpty)
        (Icons.sell_outlined, 'Tags', repo.scanner.tagsOf(a.id).join(', ')),
      if (file != null) (Icons.folder_outlined, 'Path', file.parent.path),
    ];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in rows)
            ListTile(
              dense: true,
              leading: Icon(r.$1),
              title: Text(r.$2),
              subtitle: SelectableText(r.$3),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  static String _bytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final repo = GalleryScope.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final bg = _chrome && light ? Colors.white : Colors.black;
    final fg = _chrome && light ? Colors.black87 : Colors.white;
    if (_assets.isEmpty) return const SizedBox.shrink();
    final a = _current;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: bg == Colors.white ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(children: [
          PhotoViewGallery.builder(
            pageController: _page,
            itemCount: _assets.length,
            backgroundDecoration: BoxDecoration(color: bg),
            onPageChanged: (i) => setState(() => _index = i),
            loadingBuilder: (context, _) => const SizedBox.shrink(),
            builder: (context, i) {
              final item = _assets[i];
              if (item.type == AssetType.video) {
                return PhotoViewGalleryPageOptions.customChild(
                  disableGestures: true,
                  child: _VideoPage(
                    key: ValueKey(item.id),
                    asset: item,
                    active: i == _index,
                    onTap: _toggleChrome,
                  ),
                );
              }
              return PhotoViewGalleryPageOptions(
                imageProvider: AssetEntityImageProvider(item, isOriginal: true),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 5,
                onTapUp: (_, __, ___) => _toggleChrome(),
                errorBuilder: (_, __, ___) => Center(
                    child: AssetThumb(item, size: 800, showBadges: false)),
              );
            },
          ),

          // Top bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _chrome ? 0 : -120,
            left: 0,
            right: 0,
            child: Container(
              color: bg.withOpacity(0.85),
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: Row(children: [
                IconButton(
                  color: fg,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(DateFormat('MMM d, yyyy').format(a.createDateTime),
                        style: TextStyle(
                            color: fg, fontSize: 17, fontWeight: FontWeight.w600)),
                    Text(DateFormat('h:mm a').format(a.createDateTime),
                        style: TextStyle(color: fg.withOpacity(0.6), fontSize: 12)),
                  ]),
                ),
                Text('${_index + 1}/${_assets.length}',
                    style: TextStyle(color: fg.withOpacity(0.6), fontSize: 12)),
                const SizedBox(width: 16),
              ]),
            ),
          ),

          // Bottom actions
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _chrome ? 0 : -140,
            left: 0,
            right: 0,
            child: Container(
              color: bg.withOpacity(0.85),
              padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 4, top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Action(icon: Icons.share_outlined, label: 'Send', color: fg, onTap: _share),
                  _Action(
                    icon: repo.isFavorite(a) ? Icons.favorite : Icons.favorite_border,
                    label: 'Favorite',
                    color: repo.isFavorite(a) ? Colors.redAccent : fg,
                    onTap: () => repo.toggleFavorite(a),
                  ),
                  _Action(
                      icon: Icons.delete_outline, label: 'Delete', color: fg, onTap: _delete),
                  _Action(icon: Icons.info_outline, label: 'Details', color: fg, onTap: _showInfo),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ]),
      ),
    );
  }
}

/// Plays a video only while its page is the active one.
class _VideoPage extends StatefulWidget {
  const _VideoPage({
    super.key,
    required this.asset,
    required this.active,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant _VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
    if (!widget.active && old.active) _stop();
  }

  Future<void> _start() async {
    if (_controller != null || _starting) return;
    _starting = true;
    final File? file = await widget.asset.file;
    if (file == null || !mounted) {
      _starting = false;
      return;
    }
    final c = VideoPlayerController.file(file);
    await c.initialize();
    _starting = false;
    if (!mounted || !widget.active) {
      await c.dispose();
      return;
    }
    await c.setLooping(true);
    await c.play();
    c.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _controller = c);
  }

  void _stop() {
    final c = _controller;
    _controller = null;
    c?.dispose();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return GestureDetector(
      onTap: () {
        if (ready) c.value.isPlaying ? c.pause() : c.play();
        widget.onTap();
      },
      child: Stack(alignment: Alignment.center, children: [
        if (ready)
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          )
        else
          Center(
            child: AspectRatio(
              aspectRatio: widget.asset.width > 0 && widget.asset.height > 0
                  ? widget.asset.width / widget.asset.height
                  : 16 / 9,
              child: AssetThumb(widget.asset, size: 800, showBadges: false),
            ),
          ),
        if (ready && !c.value.isPlaying)
          IconButton.filledTonal(
            iconSize: 40,
            onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
            icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
            style: IconButton.styleFrom(
                backgroundColor: Colors.black26, foregroundColor: Colors.white),
          ),
        if (ready)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 84,
            child: Row(children: [
              Text(formatDuration(c.value.position),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(formatDuration(c.value.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        if (!ready && widget.active)
          const CircularProgressIndicator(color: Colors.white),
      ]),
    );
  }
}
