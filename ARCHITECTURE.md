# Pirganj App Architecture

## Overview

Pirganj is a Flutter Android application backed by an Express API. Supabase stores application data and images, while Firebase Cloud Messaging (FCM) delivers Android system-tray notifications.

```text
Flutter Android app
  ├─ REST API client ───────────────┐
  ├─ Firebase Messaging client      │
  └─ local notification display     │
                                    ▼
                         Express backend on Render
                          ├─ Auth and JWT
                          ├─ Content and comments
                          ├─ Notification fan-out
                          ├─ FCM Admin delivery
                          └─ Supabase Storage helper
                                    │
                 ┌──────────────────┴──────────────────┐
                 ▼                                     ▼
          Supabase Postgres                     Supabase Storage
          users/content/comments                 profile/post images
                                    │
                                    ▼
                              Firebase FCM
```

## Flutter client

- `lib/main.dart` contains the app shell, page navigation, content pages, comments, notification page, and image selection UX.
- `lib/services/api_client.dart` owns authenticated REST calls and multipart uploads.
- `lib/services/push_notification_service.dart` initializes FCM, registers device tokens, handles foreground messages, and emits event-driven refresh events.
- Notification unread state is refreshed by FCM events; there is no 30-second polling loop.
- Notification taps route to the related post details or topic page.
- Selected profile and post images are compressed locally to JPEG (1600px/quality 72, then 1280px/quality 58 fallback) before the 2MB validation and upload.
- Android releases are built as `arm64-v8a` APKs with Android 14 minimum and Android 16 target/compile configuration.

## Backend

The backend exposes versionless routes under `/api`, for example `/api/posts`, `/api/notifications`, and `/api/devices/push-token`.

- `src/server.js`: Express app, middleware, CORS, and `/api` mounting.
- `src/api.js`: authenticated REST routes and request validation.
- `src/auth.js`: registration, login, JWT authentication, and profile ownership.
- `src/store.js`: Supabase-backed content access with local fallback data for tests.
- `src/notifications.js`: notification persistence, unread state, deletion, broadcast fan-out, and parent-post resolution.
- `src/push.js`: Firebase Admin device-token registration and FCM delivery.
- `src/storage.js`: Supabase Storage upload and cleanup with a 2MB safety limit.

## Notification flow

1. A user creates a post, blood request, lost/found record, service, donor record, notice, or job.
2. The API persists the record.
3. The API fans out an in-app notification to other users.
4. `src/push.js` sends FCM messages to registered Android tokens.
5. The app shows the system notification and refreshes the unread badge from the FCM event.
6. Opening the notification navigates to the related post or topic.

Comments and reactions resolve their parent post ID so their notifications also open the correct post.

## Required production configuration

Set secrets only in Render/Supabase/Firebase secret managers. Do not commit service-account JSON, private keys, JWT secrets, or Supabase secret keys.

- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `JWT_SECRET`
- `FIREBASE_SERVICE_ACCOUNT_JSON`
- `SUPABASE_IMAGE_BUCKET` (defaults to `pirganj-images`)
- `CORS_ORIGINS`
- `NODE_ENV=production`

## Verification

- Flutter widget tests pass.
- Backend Node tests pass.
- Release APK is built with `arm64-v8a` native code.
- Image uploads are compressed client-side and rejected if the compressed result remains above 2MB.
