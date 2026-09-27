# Task Checkpoints

## Checkpoint 1
- Created the Flutter Android app with private SQLite/media storage, collections, camera capture, and square JPEG processing.
- Added 60-second voice notes, 24-hour optional-field editing, Deleted restoration, and 30-day purge.
- Added Photo Picker import with EXIF date/GPS handling and explicit photo export to the gallery.
- Added versioned card/collection ZIP export with SHA-256 checks, Save to Files, and Share actions.
- Verified core flows on an API 37 emulator; analysis, 16 tests, and debug APK build pass.
- Recorded completed work, resolved issues, tooling, and remaining checks in `current.summary.md`.

## Checkpoint 2
- Replaced the home screen's action icons with a side drawer for Home, Import, Export, Deleted, and Info.
- Added an Info screen with a short app description and local-storage explanation.
- Centered the icon-only camera button at the bottom of the home screen.
- Added "Add new" to the bottom of the collection picker and kept new collections selected after creation.
- Updated the widget test; Flutter analysis, all 16 tests, and the debug APK build pass.
- Checked the home screen, drawer, and collection picker on the Android emulator.

## Checkpoint 3
- Replaced the collection card list with a pinch-adjustable grid, starting at 3 columns and bounded to 1–10.
- Centralized big (1–3), medium (4–6), and small (7–10) tile display settings.
- Kept full card content in big tiles, image and date in medium tiles, and image only in small tiles.
- Preserved scroll position when pinching between full-card and compact grid modes.
- Verified the default layout on the emulator; analysis, all 21 tests, and the debug APK build pass.

## Checkpoint 4
- Opened gallery cards in a centered modal over a 50% black backdrop instead of a full page.
- Made taps above or below the card dismiss the modal while retaining card actions and content.
- Verified opening and backdrop dismissal in a widget test and on the Android emulator.
- Flutter analysis, all 22 tests, and the debug APK build pass.
