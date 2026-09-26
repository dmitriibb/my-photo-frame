# My Photo Frame

My Photo Frame is a private gallery for memories. A memory is a square photo presented as a Polaroid-style card with a visible date, optional short text, optional voice note, and a location marker when location data is available.

Android implementation has begun in [mobile-app/](mobile-app/). The source idea is [idea.md](idea.md), and the implementation sequence is in [plan.main.md](plan.main.md).

## Product direction

The first release is an **Android app that works entirely on the device**. A user can take a photo, add text and/or a hold-to-record voice note, and save the card. For 24 hours after the first save, the user can edit text and audio or remove any optional input, including location. Deleted cards move to a Deleted area, where they can be restored until they are automatically purged after 30 days. The app can also import a gallery photo, create and switch between collections, export a photo to the device gallery, and export a collection as one shareable file. The initial collection is **Default**.

Photos captured in the app stay in private app storage until the user exports them. Card metadata belongs in a local database; image and audio bytes belong in app-private files. This keeps the gallery private while making later export possible.

After the Android app is ready, work moves to a `web-app/`. Cloud storage, sharing through accounts, and email one-time-code authentication belong to a later `backend/` phase. The web technology and backend design are undecided.

## Why Flutter for Android

Flutter is a good fit for the Android-first app: it supports a custom card UI and has practical camera, local database, file storage, and microphone integrations. The key implementation detail is the square photo requirement. Camera output dimensions can vary by device, so the app should show a square framing guide and verify/crop the saved image to 1:1 before compressing it to **at most 1,000,000 bytes**. Imported photos should follow the same card-image pipeline.

The choice of Flutter for Android does **not** decide the later web stack. Browser storage, file access, camera, and audio behave differently; evaluate the web implementation after the Android behavior and export format are stable.

## Planned repository layout

```text
idea.md          Original product idea
plan.main.md     Android-first implementation plan
AGENTS.md        Instructions for agents working in this repository
mobile-app/      Flutter Android app
web-app/         Future web app
backend/         Future cloud API and storage
```

The first two implementation milestones provide the local database, private media storage, camera capture, square photo processing, optional text and voice notes (up to 60 seconds), and the initial Default gallery and detail screens. Collection management and card lifecycle are next in the plan.

## Assumptions and open decisions

- **Assumption:** A location icon means the card actually contains location coordinates, not merely that device location is enabled. Location is optional and requires permission for new captures.
- **Assumption:** If an imported photo has no usable capture date in its metadata, use a documented fallback date so every card still shows a date.
- **Assumption:** The photo, displayed date, and collection assignment are fixed after the first save; the 24-hour edit window applies to text, audio, and removing optional inputs.
- **Decision:** Android API 24 minimum and a 60-second voice-note limit. Use an emulator during early implementation and Dima's Xiaomi 14 for later physical-device verification.

## References behind the platform choice

- [Flutter camera recipe](https://docs.flutter.dev/cookbook/plugins/picture-using-camera) and [camera plugin](https://pub.dev/packages/camera)
- [Flutter SQLite guidance](https://docs.flutter.dev/cookbook/persistence/sqlite) and [app file paths](https://pub.dev/packages/path_provider)
- [Android app-specific storage and gallery export](https://developer.android.com/training/data-storage/use-cases)
- [Android Photo Picker](https://developer.android.com/training/data-storage/shared/photo-picker)
- [CameraX resolution and crop behavior](https://developer.android.com/media/camera/camerax/configuration)
- [Flutter web considerations](https://docs.flutter.dev/platform-integration/web/faq)
