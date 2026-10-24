import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'data/gallery_scope.dart';
import 'data/media_repository.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GalleryApp());
}

/// Owns the single [MediaRepository] instance and exposes it through
/// [GalleryScope] so every screen can reach it with `GalleryScope.of(context)`.
class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  final MediaRepository _repo = MediaRepository();

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GalleryScope(
      repo: _repo,
      child: MaterialApp(
        title: 'Gallery',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const PermissionGate(),
      ),
    );
  }
}

/// Asks for media permission, then shows the main shell.
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  PermissionState? _state;

  @override
  void initState() {
    super.initState();
    _request();
  }

  Future<void> _request() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: true,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _state = state);
    if (state.hasAccess) {
      // listen: false -> we only want to kick the load off, not rebuild here.
      GalleryScope.of(context, listen: false).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state != null && state.hasAccess) return const HomeShell();

    return Scaffold(
      body: GradientBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: state == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.photo_library_outlined, size: 72),
                      const SizedBox(height: 20),
                      Text('Allow access to your photos',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text(
                        'Gallery needs permission to show the photos and videos '
                        'on this phone. Nothing leaves your device.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _request,
                        child: const Text('Allow access'),
                      ),
                      TextButton(
                        onPressed: PhotoManager.openSetting,
                        child: const Text('Open settings'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
