#!/usr/bin/env bash
set -euo pipefail

# Standard Pirganj release build:
# - compile/target SDK 36 (Android 16)
# - minSdk 34 (Android 14)
# - creates the arm64-v8a APK used by modern Android 14–16 devices

if [[ -f /home/ubuntu/pirganj-tools-env.sh ]]; then
  # shellcheck disable=SC1091
  source /home/ubuntu/pirganj-tools-env.sh
fi

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
flutter analyze --no-fatal-infos
flutter test --reporter expanded
flutter build apk --release --split-per-abi

# Keep only the requested arm64-v8a artifact; do not distribute other ABIs.
rm -f build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk \
      build/app/outputs/flutter-apk/app-x86_64-release.apk

printf '\nGenerated Android 14–16 arm64 APK:\n'
ls -lh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
