#!/usr/bin/env bash
set -euo pipefail

# Standard Pirganj release build:
# - compile/target SDK 36 (Android 16)
# - keeps the Flutter minSdk for Android 14+ compatibility
# - creates one small APK per CPU architecture instead of a 50MB universal APK

if [[ -f /home/ubuntu/pirganj-tools-env.sh ]]; then
  # shellcheck disable=SC1091
  source /home/ubuntu/pirganj-tools-env.sh
fi

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
flutter analyze --no-fatal-infos
flutter test --reporter expanded
flutter build apk --release --split-per-abi

printf '\nGenerated Android 14–16 compatible split APKs:\n'
ls -lh build/app/outputs/flutter-apk/app-*-release.apk
