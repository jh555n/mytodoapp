#!/usr/bin/env bash
set -euo pipefail
cd /workspace/mytodoapp
source tool/cloud_env.sh

for dependency in git curl unzip python3 node apt-get dpkg-deb; do
  command -v "$dependency" >/dev/null || {
    printf 'Required tool missing: %s\n' "$dependency" >&2
    exit 1
  }
done

if [[ ! -x "$JAVA_HOME/bin/javac" ]]; then
  # The base image has only a JRE and no sudo. Extract authenticated Debian
  # packages into the workspace without changing the system installation.
  mkdir -p /workspace/scratch/apt-lists/partial /workspace/scratch/java-packages
  cat > /workspace/scratch/java-packages/sources.list <<'SOURCES'
deb https://deb.debian.org/debian trixie main
deb https://security.debian.org/debian-security trixie-security main
SOURCES
  apt_options=(
    -o Dir::Etc::sourcelist=/workspace/scratch/java-packages/sources.list
    -o Dir::Etc::sourceparts=-
    -o Dir::State::lists=/workspace/scratch/apt-lists
  )
  apt-get "${apt_options[@]}" -o APT::Update::Error-Mode=any update
  java_unpack=$(mktemp -d /workspace/scratch/jdk-packages.XXXXXX)
  (
    cd "$java_unpack"
    apt-get "${apt_options[@]}" download openjdk-21-jdk-headless openjdk-21-jre-headless
    for package in ./*.deb; do
      dpkg-deb --extract "$package" /workspace/jdk-21
    done
  )
fi
javac -version
flutter_jdk_dir="$JAVA_HOME"

if [[ ! -d "$FLUTTER_ROOT" ]]; then
  git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
fi
flutter_commit=$(git -C "$FLUTTER_ROOT" rev-parse HEAD)
if [[ "$flutter_commit" != abaf9c523780a608bd46686fd5e53740a07077f8 ]]; then
  printf '%s\n' 'Expected Flutter 3.47.7. Existing SDK was preserved; use a separate SDK path to upgrade.' >&2
  exit 1
fi
flutter config --no-analytics
flutter config --jdk-dir "$flutter_jdk_dir"
flutter --version

mkdir -p /workspace/scratch "$ANDROID_HOME" "$GRADLE_USER_HOME"
if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  android_archive=/workspace/scratch/commandlinetools-linux-16111833_latest.zip
  curl --fail --location --retry 3 \
    https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip \
    --output "$android_archive"
  # Official repository2-1.xml checksum for this pinned archive.
  printf 'e025545c62a8e64c7559119566a569fb1dec5f60  %s\n' "$android_archive" | sha1sum --check
  android_unpack=$(mktemp -d /workspace/scratch/android-tools.XXXXXX)
  unzip -q "$android_archive" -d "$android_unpack"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  mv "$android_unpack/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rmdir "$android_unpack"
fi
sdkmanager --sdk_root="$ANDROID_HOME" \
  'platform-tools' 'platforms;android-34' 'platforms;android-35' 'platforms;android-36' \
  'build-tools;36.0.0' 'ndk;28.2.13676358' 'cmake;3.22.1'
flutter config --android-sdk "$ANDROID_HOME"

# Java/Gradle do not automatically inherit HTTP(S)_PROXY. Preserve existing
# user properties and add only this environment's proxy properties.
python3 - <<'PY'
import json
import os
from pathlib import Path
from urllib.parse import urlparse

policy = Path('/etc/codex/network-policy.json')
proxy = (json.loads(policy.read_text()).get('http_proxy') if policy.exists()
         else os.environ.get('HTTPS_PROXY') or os.environ.get('https_proxy'))
if proxy:
    address = urlparse(proxy)
    if not address.hostname or address.username or address.password:
        raise SystemExit('Expected a host-only environment proxy without credentials.')
    properties = Path(os.environ['GRADLE_USER_HOME']) / 'gradle.properties'
    updates = {
        'systemProp.http.proxyHost': address.hostname,
        'systemProp.http.proxyPort': str(address.port or 80),
        'systemProp.https.proxyHost': address.hostname,
        'systemProp.https.proxyPort': str(address.port or 80),
        'systemProp.http.nonProxyHosts': 'localhost|127.*',
    }
    previous = properties.read_text().splitlines() if properties.exists() else []
    kept = [line for line in previous if line.split('=', 1)[0].strip() not in updates]
    properties.write_text('\n'.join(kept + [f'{key}={value}' for key, value in updates.items()]) + '\n')
PY

bash tool/bootstrap.sh
flutter precache --android
printf '%s\n' 'Ready. In new shells: source /workspace/mytodoapp/tool/cloud_env.sh'
