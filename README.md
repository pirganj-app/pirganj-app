# Pirganj Flutter app

This is the Flutter/Dart client for the Pirganj REST API.

- App name: `Pirganj`
- Android package: `com.pirganj.app`
- API client: `lib/services/api_client.dart`
- Main screen: `lib/main.dart`
- Logo: `assets/pirganj_logo.jpg`

The current sandbox does not include the Flutter SDK, so APK compilation could not be run here. On a Flutter-enabled machine:

```bash
flutter create --org com.pirganj --project-name pirganj .
# keep the generated android/ios/web folders, then keep this project's lib/, assets/ and pubspec.yaml content
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Before running, replace `https://your-pirganj-api.onrender.com` in `lib/main.dart` with the live Render backend URL.
