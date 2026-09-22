# Medication Reminder

A privacy-focused Flutter medication reminder for iOS, Android, and macOS.

## What the app does

- Scans medication labels with Apple Vision on Apple platforms and ML Kit fallback.
- Requires users to review OCR results before saving.
- Builds conservative schedules and leaves ambiguous directions for manual review.
- Schedules friendly local reminders with Taken and Missed actions.
- Stores medication information locally with encryption and supports optional account sync.
- Shows adherence, refill, and dose history reports.

## Run locally

```sh
flutter pub get
flutter test
flutter run
```

Before running Firebase features, create your own Firebase project and run:

```sh
flutterfire configure
```

This generates the local `firebase_options.dart`, `google-services.json`, and
`GoogleService-Info.plist` files. Live Firebase configuration is intentionally
excluded from this public repository. Redacted examples are included to show
the expected file structure.

Android development also requires Android Studio or an Android SDK with `ANDROID_HOME` configured. iOS development requires Xcode and CocoaPods.

## Release notes

- Android and iOS use the shared production identity `com.phongtruong.medicationreminder`, with matching Firebase apps.
- Android release signing uses `android/key.properties`. Copy `android/key.properties.example`, create a private upload key, and never commit either the key or its passwords.
- Apple Watch notification mirroring can work from iPhone, but a full watch companion app still requires a watchOS target in Xcode and testing with a paired Watch.
- Optional crash reports are disabled by default and can be enabled in Settings. Medication details are not attached to reports.

See [RELIABILITY_TEST_CHECKLIST.md](RELIABILITY_TEST_CHECKLIST.md) before a beta or store release.
