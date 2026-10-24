# Why you only see the increment counter

**Short answer:** the APK you installed is *not* built from the code in `app.txt`. It is the stock
`flutter create` template (`MyApp` → `0` → `+`). Nothing in your gallery code is in that build —
and even if it were, it could not compile, because the pasted project is **two different apps
merged together**, with duplicate classes, missing classes and missing imports.

Line numbers below refer to `uploads/app.txt`.

---

## 1. Where the counter comes from

Your own CI file says it out loud (app.txt lines 3197-3198):

```yaml
# Creates the missing Android Gradle files, then puts OUR files back
# (flutter create writes a default counter app / pubspec / manifest).
```

`flutter create --platforms=android .` generates `lib/main.dart` = the **counter app**, plus a
default `pubspec.yaml` and `AndroidManifest.xml`. Your workflow then tries to copy the real files
back (app.txt line 3204):

```yaml
cp gallery_app/gallery_app/android/app/src/main/AndroidManifest.xml /tmp/keep/AndroidManifest.xml
```

That path is wrong for a repo-root checkout (`actions/checkout` puts the repo at
`/home/runner/work/<repo>/<repo>/`, so the manifest is at
`android/app/src/main/AndroidManifest.xml` — note your own existence check one step earlier uses
exactly that path). If any of those `cp`/`rm` lines fail, the default `lib/main.dart` written by
`flutter create` survives and the job still uploads an APK… of the counter app.

The other equally common cause: **`lib/` and `pubspec.yaml` were never committed/pushed**, so the
checkout only contained the workflow file. Then `flutter create .` builds the counter template from
scratch and everything "succeeds".

> Check the run log for the step `Generate Android project files`. If you do **not** see the line
> `lib/main.dart is the gallery app`, the restore never happened.

---

## 2. Blockers that stop the real code from compiling

Even after the APK problem is fixed, `flutter build apk` fails. These are hard errors:

| # | Problem | Where |
|---|---------|-------|
| 1 | **`PermissionGate` declared twice** (two different versions pasted into one file), plus `_PermissionGateState` twice | `main.dart` lines 23 & 50 |
| 2 | `main.dart` imports `permission_handler` but uses `PhotoManager`, `PermissionRequestOption`, `AndroidPermission`, `RequestType`, `GalleryScope`, `GradientBackground` — **none of them imported** | lines 2-4 |
| 3 | The first `PermissionGate` takes a required `child`; the second takes none. `home: const PermissionGate(child: HomeShell())` only matches the first one | line 17 vs 51 |
| 4 | `MaterialApp` never uses `buildTheme()` and there is **no `GalleryScope` ancestor**, yet every screen calls `GalleryScope.of(context)` → `No GalleryScope found in context` assertion | lines 12-19 |
| 5 | **`MediaRepository` declared twice** — a 20-line demo (`getRecentImages`) and the real `ChangeNotifier` one | `repository.dart` line 298 & `media_repository.dart` line 334 |
| 6 | The real `media_repository.dart` has **no imports at all** — it uses `Timer`, `unawaited`, `MethodCall`, `SharedPreferences`, `DateFormat`, `SmartScanner`, `Memory`, `buildMemories`, `AlbumInfo` | line 334+ |
| 7 | **`AlbumInfo` is never defined anywhere** in the project (used 7×: repo fields, `albums_screen.dart`, `search_screen.dart`) | — |
| 8 | **`ShellInsets` is never defined anywhere** (used 6×: `photos_screen.dart` 2327-2328, `albums_screen.dart` 1404/1461, `explore_screen.dart` 1642/1764) | — |
| 9 | **The real `home_shell.dart` is missing.** Only the demo version exists (lines 1891-1955) — it instantiates `MediaRepository()` itself, never provides `GalleryScope`, and has no `ShellInsets`, no tabs, no `PhotosScreen`/`AlbumsScreen`/`ExploreScreen`. Yet `albums_screen.dart` (1368), `explore_screen.dart` (1605) and `photos_screen.dart` (2211) all `import 'home_shell.dart'` **for `ShellInsets`** | — |
| 10 | **File names don't match the imports**: header says `repository.dart` but everything imports `../data/media_repository.dart`; header says `smartsanner.dart` but `explore_screen.dart` imports `../data/smart_scanner.dart`; header says `album.dart` but it defines `AlbumsScreen` used by the shell | lines 294, 655, 1359 |
| 11 | `gallery_scope.dart` imports `media_repository.dart` (line 196) → wrong if the file is really `repository.dart` | — |
| 12 | `albums_screen.dart` uses `MediaType` / `AlbumInfo` but never imports `media_repository.dart` / `album_info.dart` | 1360-1368 |
| 13 | **`pubspec.yaml` is broken**: `google_mlkit_*`, `geocoding`, `shared_preferences`, `path_provider`, `intl` are nested **inside the `flutter:` section** (so they are not dependencies at all), there is a **second `dev_dependencies:` and a second `flutter:` block** (duplicate mapping key → `pub get` exits 66), and `photo_manager_image_provider`, `photo_view`, `share_plus`, `video_player` are **missing entirely** although `common.dart`/`viewer_screen.dart` import them | 3110-3151 |
| 14 | The file is even named `pubsec.yaml` (typo) in your paste | 3110 |
| 15 | `sdk: '>=3.0.0 <4.0.0'` is too loose — the code uses records `(IconData, String, String)`, `switch` expressions and patterns (Dart 3), and `SliverList.separated` / `SliverAppBar.large` need a recent Flutter | 3117 |

### `flutter pub get` on your current pubspec (verified)

Two problems, independently fatal:

**a) Duplicate keys** – relative to the `pubsec.yaml` header (app.txt line 3110):

```
line 18:  dev_dependencies:      ← first
line 23:  flutter:               ← first (holds the ML Kit / geocoding / intl entries)
line 38:  dev_dependencies:      ← DUPLICATE
line 41:  flutter:               ← DUPLICATE (only uses-material-design)
```

A strict YAML parser (which `pub` uses) rejects this:

```
Duplicate mapping key 'dev_dependencies' at line 38
```

A lenient parser keeps only the *last* value of each key, which means the entire first `flutter:`
block — i.e. `google_mlkit_image_labeling`, `google_mlkit_face_detection`, `geocoding`,
`shared_preferences`, `path_provider`, `intl` — silently disappears. Verified: the effective
dependency list of your pasted pubspec is only

```
flutter, photo_manager ^3.0.0, permission_handler ^11.0.0
```

**b) Therefore every one of these imports is unresolved:**
`package:photo_manager_image_provider/...` (common.dart, memories_screen.dart, viewer_screen.dart),
`package:photo_view/...`, `package:share_plus/...`, `package:video_player/...` (viewer_screen.dart),
`package:google_mlkit_image_labeling/...`, `package:google_mlkit_face_detection/...`,
`package:geocoding/...`, `package:path_provider/...`, `package:shared_preferences/...`
(smart_scanner.dart), `package:intl/...` (grouping.dart, memories.dart, search_screen.dart,
viewer_screen.dart).

---

## 3. Runtime / logic bugs you'll hit after it compiles

1. `_resolvePlaceNames()` — `firstWhere(..., orElse: () => null)` on a `List<String?>` whose element
   type is non-nullable `String`. It compiles (closure return type is inferred) but **throws at
   runtime** when no place component is non-empty. Fix:
   ```dart
   final parts = [p.subLocality, p.locality, p.subAdministrativeArea, p.administrativeArea];
   String? name;
   for (final s in parts) {
     if (s != null && s.trim().isNotEmpty) { name = s; break; }
   }
   _placeNames[e.key] = name ?? 'Unknown place';
   ```
2. `repository.dart`'s demo used `ps.isAuth` (full access only). The real app should use
   `ps.hasAccess` so Android 14 "Select photos" (limited) still works. Both exist on
   `PermissionState` (`isAuth` = authorized only, `hasAccess` = authorized **or** limited).
3. `AssetThumb` calls `GalleryScope.of(context)` with `listen: true` inside every grid cell, so
   *every* thumbnail rebuilds whenever the repo notifies (which happens every 40 scanned photos).
   Pass `listen: false` or wrap the badge in a small `ListenableBuilder`.
4. `Zoom` pinch order is inconsistent: the enum is `{years, months, all, days}` but `_ZoomSwitcher._order`
   is `[years, months, days, all]`, so pinch-out from "Months" lands on "All" while the pill shows
   "Days" next to it. Reorder the enum to `{years, months, days, all}`.
5. `media_repository.load()` reads **every** album on the device into memory (`_readAll` for each
   path). On a phone with 20k photos and many albums that is slow and RAM-heavy; consider only
   reading `path.isAll` plus album *counts*, and lazily loading album contents.
6. `search()` builds `' favorite favourites'` — "favourites" (British spelling) will never match.
7. `PhotosScreen` `RefreshIndicator.onRefresh: repo.load` returns immediately when `loading == true`,
   so the spinner disappears before the reload finishes.
8. `share_plus` 10.x deprecates `Share.shareXFiles` → use `SharePlus.instance.share(ShareParams(files: ...))`.
9. `permission_handler` is in your pubspec but the fixed `main.dart` no longer needs it
   (`photo_manager` handles the media permission). Drop it to keep the APK smaller.

---

## 4. The real folder structure (from the import graph)

Your paste mixes headers with the paths the imports actually require:

```
gallery_app/
├── pubspec.yaml
├── android/app/src/main/AndroidManifest.xml
├── .github/workflows/build-apk.yml
└── lib/
    ├── main.dart                     # "main.dart file"        (only ONE PermissionGate)
    ├── theme.dart                    # "theme.dart file"
    ├── data/
    │   ├── gallery_scope.dart        # "galleryscope.dart"
    │   ├── media_repository.dart     # "repository.dart" → the ChangeNotifier version ONLY
    │   ├── album_info.dart           # ★ NEW – was missing
    │   ├── smart_scanner.dart        # "smartsanner.dart"  (mind the spelling!)
    │   ├── grouping.dart             # "grouping.dart"
    │   └── memories.dart             # "memories.dart"
    ├── widgets/
    │   └── common.dart               # "common.dart"
    └── screens/
        ├── home_shell.dart           # ★ REWRITTEN – defines HomeShell + ShellInsets
        ├── photos_screen.dart
        ├── albums_screen.dart        # "album.dart"  (rename the file!)
        ├── explore_screen.dart
        ├── memories_screen.dart
        ├── search_screen.dart
        ├── asset_grid_screen.dart
        └── viewer_screen.dart        # "view_screen.dart" (rename!)
```

---

## 5. What I generated for you (in `fixed/`)

| File | Status |
|------|--------|
| `fixed/lib/main.dart` | rewritten – one `PermissionGate`, creates the repo, wraps the app in `GalleryScope`, uses `buildTheme()` |
| `fixed/lib/data/media_repository.dart` | the real one, **with imports**, demo class removed |
| `fixed/lib/data/album_info.dart` | **new** – the missing `AlbumInfo` |
| `fixed/lib/screens/home_shell.dart` | **new** – the missing shell: 3 tabs, floating glass search bar, `ShellInsets` |
| `fixed/pubspec.yaml` | rewritten – all deps at the right level, no duplicate keys, Dart ≥ 3.6 |
| `fixed/.github/workflows/build-apk.yml` | rewritten – correct manifest path, loud failure if `lib/` is missing, verifies `flutter create` didn't clobber your sources |
| `fixed/android/app/src/main/AndroidManifest.xml` | your manifest + `ACTION_SEND` in `<queries>` for share_plus |

Small manual edits still needed in your existing screens:

```dart
// lib/screens/albums_screen.dart  (your "album.dart") — add these imports:
import '../data/album_info.dart';
import '../data/media_repository.dart';   // for MediaType
// and remove:  import 'home_shell.dart';  → keep it only if you use ShellInsets

// lib/screens/explore_screen.dart — fix the scanner import + drop the unused one:
import '../data/smart_scanner.dart';      // file MUST be named smart_scanner.dart
// remove:  import 'home_shell.dart';
```

---

## 6. Do this, in order

```bash
cd gallery_app

# 1. Confirm what's actually on disk / in git
git status
ls lib lib/data lib/screens lib/widgets
grep -n "MyApp\|_counter" lib/main.dart     # ← if this matches, you're on the template

# 2. Drop in the fixed files, rename album.dart → albums_screen.dart,
#    view_screen.dart → viewer_screen.dart, smartsanner.dart → smart_scanner.dart,
#    repository.dart → media_repository.dart

# 3. Local build first — never debug a Flutter app through CI
flutter clean
flutter pub get
flutter analyze          # must be 0 errors
flutter build apk --debug
flutter install          # or: flutter run -d <device>
```

Only when `flutter analyze` is clean and the debug APK shows the gallery should you push and let
the GitHub Action build the release APK.

If you build with GitHub Actions, also verify in the repo's **Actions → run log**:
* `Check gallery source files exist` → prints `Gallery source found`
* `Generate Android project files` → prints `OK  lib/main.dart is the gallery app`

If either is missing, the repo does not contain your `lib/` folder — that alone explains the
counter app.
