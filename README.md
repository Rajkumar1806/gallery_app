# Gallery (ColorOS-style) — repaired project skeleton

This folder contains **every Dart source file** of the app, with the compile blockers fixed,
plus a working `pubspec.yaml`, `AndroidManifest.xml` and GitHub Actions workflow.

It is a **skeleton**: it has no `android/` Gradle files, no `ios/`, no icons. Those are generated
by `flutter create` in step 2 below (that is exactly what the CI workflow does too).

---

## What was repaired

| File | Change |
|------|--------|
| `lib/main.dart` | Removed the duplicate `PermissionGate`. Now creates one `MediaRepository`, wraps the app in `GalleryScope`, uses `buildTheme()`, imports `photo_manager` / `theme.dart` / `gallery_scope.dart`. |
| `lib/data/media_repository.dart` | Kept only the real `ChangeNotifier` version (the 20-line `getRecentImages` demo was deleted) and added the imports it was missing (`dart:async`, `flutter/services`, `intl`, `shared_preferences`, `album_info`, `memories`, `smart_scanner`). |
| `lib/data/album_info.dart` | **New.** `AlbumInfo` was used 7× and defined nowhere. |
| `lib/screens/home_shell.dart` | **New.** The real shell: Photos / Albums / Explore tabs, floating glass search bar, and the `ShellInsets` helper used by 3 screens — none of it existed. |
| `lib/screens/albums_screen.dart` | Renamed from `album.dart` (it defines `AlbumsScreen`); added the missing `album_info.dart` import. |
| `lib/screens/viewer_screen.dart` | Renamed from `view_screen.dart` (`common.dart` imports `../screens/viewer_screen.dart`). |
| `lib/data/smart_scanner.dart` | Renamed from `smartsanner.dart` (`explore_screen.dart` imports `smart_scanner.dart`). Fixed `firstWhere(orElse: () => null)` → plain loop; the old form throws a runtime `TypeError` because the list element type is non-nullable `String`. |
| `lib/screens/photos_screen.dart` | `enum Zoom` reordered to `{years, months, days, all}` so pinch-zoom steps in the same order as the on-screen switcher. |
| `pubspec.yaml` | Was broken: `dev_dependencies` and `flutter:` appeared twice (duplicate mapping key → `pub get` fails), and ML Kit / geocoding / shared_preferences / path_provider / intl were nested **inside** `flutter:` so they were not dependencies at all. `photo_manager_image_provider`, `photo_view`, `share_plus`, `video_player` were missing entirely. Dart SDK bumped to `>=3.6.0` (the code uses records + patterns). |
| `.github/workflows/build-apk.yml` | Correct manifest path, `set -euo pipefail`, hard failure if `lib/` is missing, and verification that `flutter create` did not clobber the gallery sources. |
| `android/app/src/main/AndroidManifest.xml` | Your manifest + `ACTION_SEND` in `<queries>` so `share_plus` can resolve targets on Android 11+. |

Everything else (`theme.dart`, `gallery_scope.dart`, `grouping.dart`, `memories.dart`,
`common.dart`, `explore_screen.dart`, `photos_screen.dart`, `search_screen.dart`,
`memories_screen.dart`, `asset_grid_screen.dart`, `viewer_screen.dart`) is your code unchanged.

---

## Build it

```bash
cd gallery_app

# 1. sanity check the sources are the gallery, not the template
grep -q PermissionGate lib/main.dart && echo "OK: gallery main.dart"

# 2. generate the android/ + ios/ scaffolding WITHOUT touching lib/ or pubspec.yaml
flutter create --platforms=android --org com.coresolutions --project-name gallery_app .

# 3. put our manifest back (flutter create writes a default one)
#    (only needed if you already had a custom manifest; step 2 does not delete an existing one)

# 4. ML Kit needs API 24+
sed -i -E 's/minSdk[[:space:]]*=[[:space:]]*(flutter\.minSdkVersion|[0-9]+)/minSdk = 24/' \
  android/app/build.gradle.kts

# 5. build
flutter clean
flutter pub get
flutter analyze          # must report 0 errors
flutter build apk --debug
flutter install          # or: flutter run -d <device-id>
```

> **Do not debug through CI.** Get `flutter analyze` clean and the debug APK on a phone first,
> then push and let the Action build the release APK.

### Required Flutter/Dart version

`SliverList.separated`, `SliverAppBar.large`, records and `switch` expressions →
**Flutter 3.27+ / Dart 3.6+**. Check with `flutter --version`.

---

## Folder layout

```
gallery_app/
├── pubspec.yaml
├── analysis_options.yaml
├── .gitignore
├── .github/workflows/build-apk.yml
├── android/app/src/main/AndroidManifest.xml
└── lib/
    ├── main.dart
    ├── theme.dart
    ├── data/
    │   ├── album_info.dart          ★ new
    │   ├── gallery_scope.dart
    │   ├── grouping.dart
    │   ├── media_repository.dart    ★ rewritten
    │   ├── memories.dart
    │   └── smart_scanner.dart       ★ renamed + fixed
    ├── widgets/
    │   └── common.dart
    └── screens/
        ├── home_shell.dart          ★ new (HomeShell + ShellInsets)
        ├── photos_screen.dart
        ├── albums_screen.dart       ★ renamed
        ├── explore_screen.dart
        ├── memories_screen.dart
        ├── search_screen.dart
        ├── asset_grid_screen.dart
        └── viewer_screen.dart       ★ renamed
```

---

## If you build with GitHub Actions

Commit **everything** — `lib/`, `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`,
`.github/workflows/build-apk.yml`. If `lib/` is not in the repo, `flutter create` in the workflow
generates the default **counter app** and you get a green run that produced an APK showing
`0` and a `+` button. That is the exact symptom this project had.

In the run log, these two lines must appear:

```
Gallery source found
OK  lib/main.dart is the gallery app
```

---

## Known rough edges left on purpose (not compile errors)

1. `AssetThumb` reads `GalleryScope.of(context)` with `listen: true`, so every visible thumbnail
   rebuilds on each `notifyListeners()` — and the scanner notifies every 40 photos. Switch the
   favourite badge to `listen: false` or a small `ListenableBuilder` if scrolling feels heavy.
2. `MediaRepository.load()` reads **every** album's full asset list into memory. Fine for a few
   thousand photos, slow above ~20k. Consider loading only `path.isAll` eagerly and album contents
   lazily on tap.
3. `RefreshIndicator(onRefresh: repo.load)` returns immediately when a load is already running.
4. `share_plus` 10.x deprecates `Share.shareXFiles` → `SharePlus.instance.share(ShareParams(files: ...))`.
5. `search()` indexes `' favorite favourites'` — the British spelling `favourites` never matches.
6. `permission_handler` was dropped from the dependencies; `photo_manager` handles the media
   permission. Add it back only if you need other permissions.
