#!/usr/bin/env bash
# Source this file in each new shell; these values do not change HOME.
export FLUTTER_ROOT=/workspace/flutter-sdk
export ANDROID_HOME=/workspace/android-sdk
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PUB_CACHE=/workspace/.pub-cache
export GRADLE_USER_HOME=/workspace/.gradle
export JAVA_HOME=/workspace/jdk-21/usr/lib/jvm/java-21-openjdk-amd64
export PATH="$JAVA_HOME/bin:$FLUTTER_ROOT/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
