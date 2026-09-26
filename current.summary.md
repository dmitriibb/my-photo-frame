# Android implementation status — 2026-09-26

Work is paused at Dima's request. The Android app lives in `mobile-app/`; `web-app/` and `backend/` have not been started. The working tree is uncommitted. Follow `AGENTS.md`, `idea.md`, and `plan.main.md` when resuming.

## Decisions

- Flutter Android first, minimum Android API 24.
- Voice notes stop automatically at **60 seconds**.
- Use the emulator for now. Dima has a Xiaomi 14 and plans to install an APK when the app is sufficiently ready.
- Keep captured media in app-private files; SQLite stores card metadata. The photo, displayed date, and collection do not change after first save. Text/audio may change and text/audio/location may be removed for 24 hours. Soft-deleted cards remain restorable for 30 days.

## Implemented

- Flutter Android project with a `Default` collection, SQLite schema version 2, case-insensitive unique collection names, migrations, and app-private photo/audio paths. Saves roll back copied media on database failure; launch cleanup removes orphaned media.
- Camera preview with a square guide, permission/lifecycle handling, capture, orientation correction, square crop, EXIF/ICC removal, and JPEG compression to at most 1,000,000 bytes.
- Draft editor with optional text, press-and-hold AAC voice note, cancellation, playback, 60-second cutoff, collection choice, and cleanup of canceled drafts.
- Polaroid-style gallery, card detail/audio playback, collection creation and switching, 24-hour edit enforcement in the repository, individual removal of optional fields, Deleted/restore, and 30-day purge on launch/resume plus a periodic WorkManager task.
- Android Photo Picker import with a locked square crop. Native AndroidX ExifInterface reads original date, offset, and GPS before processing. The displayed EXIF calendar day is stored separately from its UTC instant; absent or malformed dates fall back to import time. Imported GPS can be omitted before save.
- Explicit **Export photo to gallery** action; captured photos stay private until this action is used.
- Card and collection ZIP creation. Version 1 JSON manifests contain IDs, dates, optional values, media paths/sizes, and SHA-256 checks. Collection ZIPs contain one ZIP per active card and exclude Deleted cards. UI offers **Save to Files** or **Share**. Temporary archives are removed after the action.
- A new **Add current location** control in a capture draft requests foreground permission only when tapped and can omit that location before saving. This latest addition has compiled but has not been run in the emulator yet.

## Verification completed

- Latest source: `flutter analyze` clean, all **16 Flutter tests** pass, and `flutter build apk --debug` succeeds. APK: `mobile-app/build/app/outputs/flutter-apk/app-debug.apk` (debug signed).
- Emulator: Pixel 10 / API 37. Capture, photo processing, a short voice note, save/restart persistence, card playback, collection create/switch, edit, soft delete/restore, Photo Picker import/crop/save, explicit gallery export, and collection Save to Files were exercised.
- Pulled an emulator-saved collection ZIP and opened it with Python's standard `zipfile` module. It contained three nested card ZIPs, including one audio clip; nested files and SHA-256 values were checked independently of the Dart ZIP reader.
- Tests cover save rollback, orphan cleanup, collection names, 24-hour edit boundary, 30-day restore/purge boundary, photo byte limit, voice cutoff/cancel/permission, EXIF date fallback and timezone day, ZIP contents/exclusion, and key widget flows. A version 1 to 2 database migration was exercised in the emulator; it has no dedicated automated test yet.

## Problems found and fixes

- The camera-to-draft navigation originally used replacement navigation and lost the save result. It now returns the result to the gallery, which refreshes immediately.
- A collection dialog controller was disposed while the dialog's closing animation still used it. The dialog now keeps the entered string in state; a widget test covers creation.
- Deleted restore passed an asynchronous expression to `setState`, which raised a Flutter error even though the database restore succeeded. The callback is synchronous now; a widget test covers it.
- The first background cleanup used sqflite's shared database instance and closed the foreground app's connection. Background work now opens with `singleInstance: false`, purges only expired cards, then closes its own connection. Emulator import and Deleted worked after this fix.
- The gallery export permission conflicted with the camera plugin's manifest `maxSdkVersion`. The app manifest explicitly overrides that value to 29, as required by the gallery package for older Android versions.
- Gradle currently warns that `workmanager_android` still applies the Kotlin Gradle Plugin and may need an upgrade for a future Flutter built-in Kotlin requirement. The current APK builds successfully.

## Remaining Android work

1. Exercise the new capture-location permission/add/omit flow in the emulator, including denial and location-services-off behavior. Test imported photos with real EXIF dates, offsets, GPS, missing metadata, rotation, and HEIC if available; confirm the stored JPEG contains no location EXIF.
2. Exercise archive **Share** and single-card Save to Files in the emulator. Document the version 1 manifest format and compatibility rules for later web/backend consumers. Ensure card export refuses a card that becomes Deleted while its detail view is open.
3. Test large collection export and low-storage behavior. The current `file_picker` Save to Files API takes a full ZIP byte buffer, so memory use may need improvement for large collections.
4. Verify periodic purge execution, permission/lifecycle edge cases, and a release-ready build. The new location feature is present in the latest debug APK but has not been installed/tested on the emulator.
5. Test core flows on Dima's Xiaomi 14 when the app is ready enough. Compare the camera square guide with the saved crop, plus microphone gestures and permissions on-device. No physical-device test has been done yet.
6. Update `mobile-app/README.md` and the root `README.md`; both still describe earlier milestones. After Android is ready, begin `web-app/`. Cloud accounts, sync, and authentication stay in the later `backend/` phase.

## Tools that could help the next agent

- Existing CLI workflow is effective: Flutter commands plus the Android SDK's `adb.exe` at `C:\Users\Dmitrii\AppData\Local\Android\Sdk\platform-tools\adb.exe`, screenshots, and `view_image`. `adb` is not on this shell's `PATH`. The emulator serial was `emulator-5554`.
- [Dart and Flutter MCP server](https://docs.flutter.dev/ai/tools) is an official option for live analyzer diagnostics, symbol lookup, tests, package management, and Flutter runtime inspection. It is **not connected in this Codex session**; investigate connecting `dart mcp-server` if the Codex host supports its stdio transport.
- [Android Studio Agent Mode](https://developer.android.com/studio/gemini/agent-mode) can deploy to a device, inspect its screen, take screenshots, read Logcat, and send `adb shell input`. That is a separate Android Studio agent workflow, not an Android Studio MCP server currently available to this Codex session. No ChatGPT Android plugin was verified or installed.
- ADB screenshots written to `/sdcard/current.png` appeared in Android Photo Picker as public media and cluttered import testing. Prefer a host-side screenshot capture method or clean those test screenshots before future picker checks.
