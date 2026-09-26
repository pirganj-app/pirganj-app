# Pirganj Flutter App

পীরগঞ্জ এলাকার স্থানীয় তথ্য, কমিউনিটি পোস্ট এবং জরুরি সেবার জন্য এটি একটি **Flutter mobile application**। App-এর backend হলো আলাদা plain Express.js REST API repository, যা Supabase database-এর সঙ্গে কাজ করে।

> **Backend repository:** [pirganj-app-backend](https://github.com/pirganj-app/pirganj-app-backend)
>
> **Live API:** [https://pirganj-app.onrender.com](https://pirganj-app.onrender.com)

## Project status

The app contains the current iOS-style Pirganj interface with a branded header, matching Android system bars, Bengali labels, compact typography, rounded cards, the supplied Pirganj logo, and API-backed data screens.

The Home screen directly shows five separate topic cards:

- রক্ত — donor data only
- রক্তের অনুরোধ
- নোটিশ
- চাকরি
- হারানো/পাওয়া

Each topic opens its own dedicated list page. The page header contains an **Add New** action and the list displays data for that topic only. New submissions are sent to the corresponding backend endpoint and are immediately visible when the list refreshes.

The current release does not yet include Google sign-in, device push notifications, or user-specific edit/delete authorization. Those features require coordinated changes in Supabase Auth, the Express backend, and this Flutter client.

## Technology stack

- **Framework:** Flutter
- **Language:** Dart
- **Android package:** `com.pirganj.app`
- **Minimum Dart SDK:** `>=3.3.0 <4.0.0`
- **HTTP client:** `package:http`
- **Icons/UI:** Flutter Material 3 and Cupertino Icons
- **Backend:** Express.js REST API
- **Database:** Supabase PostgreSQL through the backend
- **Primary locale:** Bengali (`bn-BD`)

This repository contains only Flutter/Dart mobile code. It does not contain the Express backend or Supabase secret keys.

## Repository structure

```text
.
├── android/                         # Android project and package configuration
├── assets/
│   └── pirganj_logo.jpg             # App logo and branding asset
├── lib/
│   ├── main.dart                    # App entry point, Home, topic pages, forms
│   ├── models/service_card.dart      # Service data model
│   └── services/api_client.dart     # REST API client and create operations
├── test/
│   └── widget_test.dart             # Widget tests with deterministic mock API
├── analysis_options.yaml             # Dart analyzer rules
├── pubspec.yaml                      # Flutter dependencies and assets
└── pubspec.lock                      # Locked dependency versions
```

## Requirements

Install the following on the development machine:

- Flutter stable channel
- Dart SDK supplied by Flutter
- Android SDK and an Android emulator or physical device for Android testing
- Java 17 for release builds

Check the installation with:

```bash
flutter doctor
```

## Setup and run

Clone the repository and install dependencies:

```bash
git clone https://github.com/pirganj-app/pirganj-app.git
cd pirganj-app
flutter pub get
```

Run on a connected device or emulator:

```bash
flutter run
```

The current API base URL is configured in `lib/main.dart`:

```dart
PirganjApiClient(baseUrl: 'https://pirganj-app.onrender.com')
```

For another backend environment, update this value or refactor it into a build-time configuration before creating a release build. Do not place Supabase credentials in the Flutter application; only the public backend URL belongs in the client.

## Validation commands

Run static analysis and widget tests before building:

```bash
flutter analyze
flutter test --reporter expanded
```

The widget tests cover the Home screen, topic navigation, category detail pages, Add New actions, and the donor-only Blood page. The tests use a deterministic mock HTTP client and do not require a live network connection.

## Release APK

Build an installable release APK with:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The generated APK is located at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

The release package is `com.pirganj.app`. Before distributing a release, confirm the package, app label, launcher icon, Android manifest, and archive integrity with Android SDK tooling. A production release should also use a protected signing key that is never committed to this repository.

## Main API operations

The API wrapper is implemented in `lib/services/api_client.dart`.

| Dart operation | HTTP method | Backend route |
|---|---:|---|
| `getServices()` | GET | `/api/services` |
| `getPosts()` | GET | `/api/posts` |
| `createPost()` | POST | `/api/posts` |
| `getDonors()` | GET | `/api/donors` |
| `createDonor()` | POST | `/api/donors` |
| `getBloodRequests()` | GET | `/api/blood-requests` |
| `createBloodRequest()` | POST | `/api/blood-requests` |
| `getNotices()` | GET | `/api/notices` |
| `createNotice()` | POST | `/api/notices` |
| `getJobs()` | GET | `/api/jobs` |
| `createJob()` | POST | `/api/jobs` |
| `getLostFound()` | GET | `/api/lost-found` |
| `createLostFound()` | POST | `/api/lost-found` |

All requests expect the backend response envelope:

```json
{
  "success": true,
  "data": []
}
```

The API client throws an exception for an HTTP error or a response with `success: false`. The UI provides loading, empty, and error states around the API-backed screens.

## UI behavior

The app starts with the branded Home screen. The top app bar and the Android status/navigation system bars use the Pirganj brand color. The Home screen includes service search and category cards in addition to the five direct topic cards.

Topic pages use one data source per topic. The Blood page calls the donors endpoint only, so blood request records are not mixed into the donor list. The Add New action opens the matching form, submits through `PirganjApiClient`, and reloads the matching list after success.

The app uses the supplied logo at `assets/pirganj_logo.jpg`. Android launcher icon resources are included under `android/app/src/main/res/mipmap-*`.

## Data and authentication notes

The Flutter app currently sends public create requests to the backend. It does not yet maintain a Supabase Auth session and does not send a user JWT. Therefore, the current backend cannot safely determine which user owns a record.

When authentication is added, the implementation should:

1. Sign the user in through Supabase Auth or Google OAuth.
2. Store the session securely on the device.
3. Send the access token with protected API requests.
4. Let the Express backend verify the token server-side.
5. Let the backend, not the client, set and check the record owner.

Do not implement ownership by trusting a user ID supplied in a form field.

## Push notifications roadmap

Device notifications for blood requests, notices, jobs, and app updates are not enabled in this release. A future implementation will require Firebase Cloud Messaging in Flutter, device-token registration in Supabase, Firebase Admin SDK in Express, and server-side matching by blood group or area.

## Contributing workflow

Keep the application plain Flutter/Dart and preserve the existing Bengali UI language and brand styling. When adding a feature, update the API client, the relevant page/form, and the widget tests together. Run `flutter analyze` and `flutter test` before committing.

Do not commit the following files:

- `.dart_tool/`
- `build/`
- `android/local.properties`
- signing keys such as `.jks` or `.keystore`
- `google-services.json` if it contains environment-specific credentials
- any `.env` file or backend secret

## Related repositories

- [Flutter app repository](https://github.com/pirganj-app/pirganj-app)
- [Express/Supabase backend repository](https://github.com/pirganj-app/pirganj-app-backend)
- [Live API health endpoint](https://pirganj-app.onrender.com/api/health)

## References

[1]: https://docs.flutter.dev/ "Flutter documentation"
[2]: https://dart.dev/guides "Dart language and tooling guides"
[3]: https://supabase.com/docs/guides/auth "Supabase Auth documentation"
[4]: https://firebase.google.com/docs/cloud-messaging "Firebase Cloud Messaging documentation"

**Project:** Pirganj | **Mobile:** Flutter | **Backend:** Express.js | **Database:** Supabase

[1] [2] [3] [4]

## Standard Android release build

For every release, build Android 14–16 compatible low-size APKs with:

```bash
source /home/ubuntu/pirganj-tools-env.sh
./scripts/build_release_apks.sh
```

This runs analysis and widget tests, then uses `flutter build apk --release --split-per-abi`. Distribute `app-arm64-v8a-release.apk` to modern Android 14–16 phones; keep the `armeabi-v7a` build for older 32-bit devices. Do not distribute the universal `app-release.apk` when download size matters.
