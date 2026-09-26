# My Photo Frame: Android-first plan

## Decision

Use **Flutter for the Android app** in `mobile-app/`. Its camera, microphone, local persistence, and custom UI support match the idea. Use Android-specific integration only where Flutter packages do not expose needed system behavior, particularly gallery export or metadata handling. Defer the web technology choice until the Android experience and data format are proven.

No app code is part of this planning step.

## Scope and completion point

Android is ready when a user can capture or import a photo, create a dated card with optional text/audio/location, edit text and audio or remove any optional input for 24 hours after initial save, browse cards in the intended Polaroid layout, create and switch between collections, restore a soft-deleted card from Deleted, keep media private by default, export a photo to the Android gallery, and export/share a collection as one file. Deleted cards and their media are purged after 30 days. Core flows must survive app restarts and be verified on a physical Android device.

Cloud accounts, sync, remote sharing, and the web app follow Android; they are not Android release dependencies.

## Data and platform approach

- **Card:** stable ID, collection ID, displayed photo date and its source, initial save time (`created_at`), last update time, optional deletion time (`deleted_at`), optional text, optional audio path, optional location coordinates, and photo path. Keep media files outside the database in app-private storage.
- **Photo:** show a square framing guide, normalize orientation, crop the chosen area to 1:1, then resize/encode until the saved image is no larger than 1,000,000 bytes. Verify both dimensions and file size after processing. Apply the same pipeline to imported images, with a crop choice for imports. Extract needed date/location before conversion, then strip location metadata from the stored image so removing the card's location also removes it from future exports.
- **Date:** use capture time for in-app photos. For imports, prefer original capture date from image metadata, then a reliable file/media date when available, then import time. Preserve the date source; missing metadata must never leave the card dateless. Check time-zone behavior with travel photos.
- **Location:** request foreground permission only when adding capture location. Show the icon only when coordinates are actually stored. For imports, read embedded location if available. **Assumption:** there is no background location tracking.
- **Audio:** one optional voice clip per card. Start recording on press, stop on release, cancel/discard on gesture cancellation, and allow playback before saving. Handle permission denial and app interruptions without leaving broken media files.
- **Editing and deletion:** the edit deadline is `created_at + 24 hours`, measured from the first save and never extended by an edit or restore. Within that window, text and audio can be added, changed, or removed, and location can be removed independently. Show a remove action for each optional input. Remove obsolete audio files and clear location coordinates when those inputs are removed; exports must reflect the current card data. After the deadline, content is read-only, but the whole card can still be soft-deleted. Enforce the deadline in the data layer as well as the UI. Deleting sets `deleted_at`, hides the card from normal collections, and moves it to Deleted. Restoration clears `deleted_at` during the 30-day window; it does not reopen editing after the 24-hour deadline. At `deleted_at + 30 days`, purge the database row and associated media. Schedule background cleanup and sweep expired cards on app launch/resume because Android may defer background work. **Assumption:** a deleted card must be restored before it can be edited or exported.
- **Assumption:** the photo, displayed date, and collection assignment do not change after the first save. The 24-hour window covers text/audio changes and removal of optional inputs.
- **Export:** use an openly readable, versioned ZIP container. A card ZIP contains a JSON manifest, its square photo, and optional audio. A collection ZIP contains a collection manifest and one card ZIP per active card, so the entire collection and each included card are single files. Deleted cards are excluded. Prefer ordinary `.zip` names initially; a custom extension is unnecessary until a compatible importer exists. Save through the Android document picker or share with the Android share sheet. Gallery export is a separate action that writes only the image through Android MediaStore.

The main risks to verify early are whether the square preview matches the saved crop on real devices, whether imported photos retain usable EXIF dates, and whether shared archives are easy to inspect. Nested card ZIPs meet the one-file-per-card request but require a second extraction step for someone browsing a collection archive.

## Implementation sequence

### 1. Set up `mobile-app/` and the local data layer

- Create the Flutter Android project and choose its minimum Android version after checking camera/audio package requirements and intended device support.
- Define models for collections and cards, database migrations, and app-private media directories.
- Create the `Default` collection automatically. Make saving a card atomic enough that a failed save leaves neither an incomplete database row nor orphaned media.

**Done when:** the app launches on Android, creates `Default`, and saved sample cards persist across restarts.

### 2. Build capture and card creation

- Add camera preview with a square framing guide and a capture flow that handles permission denial, orientation, and camera lifecycle changes.
- Normalize the captured image to square and verify the 1 MB limit.
- Add the editor with optional short text, press-and-hold audio recording, playback, and `Done`/cancel behavior.

**Done when:** a photo can be taken, annotated, saved, reopened, and played back; canceled drafts leave no saved card.

### 3. Build the gallery, collections, and card lifecycle

- Display cards as Polaroid-style items with the date always visible and text, audio control, and location icon only when their data exists.
- Add a card detail view for the full photo and audio playback.
- Allow users to create/name collections, select a collection when saving, and switch between collections. Keep `Default` as the initial collection.
- Provide text/audio editing and separate remove actions for text, audio, and location until 24 hours after the initial save. Show the remaining edit window or deadline, then present the card as read-only.
- Add a Deleted area with deletion date and purge date, restore action, and automatic purge of expired cards and media. Keep deleted cards out of normal collections and exports.

**Done when:** cards appear in their chosen collections after relaunch; edits at or past the 24-hour deadline are rejected; deleted cards can be restored before 30 days and are purged at the next permitted cleanup after expiry.

### 4. Add gallery import and private/public media controls

- Import selected photos through the Android Photo Picker. Extract the original capture date and optional GPS data before image conversion; handle absent or malformed metadata.
- Crop/encode the imported photo through the common card pipeline.
- Add an explicit **Export photo to gallery** action through MediaStore. Confirm that new in-app photos do not appear in the system gallery before export.

**Done when:** imported photos display the best available date, and only explicitly exported photos become visible in the device gallery.

### 5. Add portable card and collection export

- Define and document ZIP manifests with `format_version`, IDs, dates, optional fields, media names, and integrity checks. Export a card as one ZIP and a collection as one ZIP containing card ZIPs.
- Support saving the archive to a user-chosen location and sharing it through the Android share sheet.
- Validate produced archives with an independent ZIP reader and check that recipients can extract the photo, text, and audio. Archive import/restore is a later feature if needed.

**Done when:** a collection exports as a readable single file and each card remains a self-contained file inside it.

### 6. Android release verification

- Test on a physical Android device: camera rotation/lifecycle, microphone press/release/cancel, permission denial, gallery import with and without EXIF dates, square dimensions, image size cap, private storage, explicit gallery export, database persistence, collections, edit deadlines, delete/restore/purge boundaries, and archive contents.
- Check large collections and low-storage failures. Fix issues found in the core flows, then produce an installable Android build.

**Done when:** all Android scope above works on-device and the build is ready for Dima to use.

## After Android

1. Start `web-app/` with a fresh decision on Flutter web versus a web-native UI, based on browser camera/audio behavior, storage needs, and sharing requirements. Keep the card/archive format compatible.
2. Add `backend/` when cloud storage, upload, remote viewing/sharing, and email one-time-code authentication are in scope. Define access controls and sync behavior at that time.

## Implementation decisions

- **Resolved:** minimum Android version is API 24, based on the selected Flutter camera and storage packages. Use an emulator during early implementation; Dima's Xiaomi 14 is available for physical-device testing when the app is ready enough to install.
- **Resolved:** voice notes have a maximum duration of 60 seconds.

## Technical references

- [Flutter camera guide](https://docs.flutter.dev/cookbook/plugins/picture-using-camera)
- [Flutter SQLite guide](https://docs.flutter.dev/cookbook/persistence/sqlite)
- [Flutter microphone recording package](https://pub.dev/packages/record)
- [Android Photo Picker](https://developer.android.com/training/data-storage/shared/photo-picker)
- [Android private and shared storage](https://developer.android.com/training/data-storage/use-cases)
- [Android Storage Access Framework](https://developer.android.com/guide/topics/providers/document-provider)
- [CameraX configuration](https://developer.android.com/media/camera/camerax/configuration)
- [Android EXIF date metadata](https://developer.android.com/reference/androidx/exifinterface/media/ExifInterface)
- [Flutter web FAQ](https://docs.flutter.dev/platform-integration/web/faq)
