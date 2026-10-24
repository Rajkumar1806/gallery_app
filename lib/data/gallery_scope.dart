import 'package:flutter/widgets.dart';

import 'media_repository.dart';

/// Makes the [MediaRepository] available to the widget tree and rebuilds
/// dependants whenever it notifies.
class GalleryScope extends InheritedNotifier<MediaRepository> {
  const GalleryScope({super.key, required MediaRepository repo, required super.child})
      : super(notifier: repo);

  static MediaRepository of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<GalleryScope>()
        : context.getInheritedWidgetOfExactType<GalleryScope>();
    assert(scope != null, 'No GalleryScope found in context');
    return scope!.notifier!;
  }
}
