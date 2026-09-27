# My Photo Frame Android app

Flutter Android app under development. The app creates the `Default` collection on launch, stores card metadata in SQLite (`cards.db`), and keeps photos and audio in the app-private documents directory. Users can capture a photo with a square framing guide, add optional text or a press-and-hold voice note, save the card, reopen it, and play the voice note. Recording stops automatically at 60 seconds. Canceling a draft discards its media.

The SQLite schema is version 1. Stored media paths are relative, with forward slashes. `photo_date` records the source timestamp in UTC; `display_date` preserves the day shown on the card when the device time zone changes. The later archive export will use a separate versioned manifest.

Camera photos are normalized for orientation, center-cropped to 1:1, encoded as JPEG, stripped of source EXIF, and checked against the 1,000,000-byte cap before being saved. `CardRepository.saveCard` expects this processed JPEG. Gallery import will use the same pipeline later.

Run `flutter test` for persistence, photo processing, recording-limit, and cleanup checks. Run `flutter run -d <android-device>` on an emulator or physical device to launch the app. Early capture/save/playback verification was performed on an Android emulator; physical-device checks on Dima's Xiaomi 14 are deferred until the app is ready enough to install.

## Build a release APK

From `mobile-app/`, run:

```sh
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The current Android build configuration signs release builds with the debug key; configure a release signing key before distributing the app.
