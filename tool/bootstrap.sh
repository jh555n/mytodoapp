#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v flutter >/dev/null 2>&1; then
  printf '%s\n' 'Flutter SDK가 필요합니다. 검증 기준: Flutter 3.47.7 stable.' >&2
  exit 1
fi
if [[ ! -f android/app/build.gradle.kts || ! -f ios/Runner/Info.plist ]]; then
  flutter create --org dev.dayweave --project-name dayweave --platforms android,ios --no-pub .
fi
node tool/configure_platforms.mjs
flutter pub get
printf '%s\n' 'iOS 위젯 타깃을 등록하려면 macOS에서 ruby tool/configure_widget.rb 를 실행하세요.'
