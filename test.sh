#!/bin/bash
# Tes otomatis untuk logika inti (tanpa Xcode; cukup Command Line Tools).
# Pakai: ./test.sh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
ARCH="$(uname -m)"
# Hanya file logika murni (tanpa AppKit/SwiftUI) yang ikut dites.
xcrun swiftc \
  -parse-as-library \
  -swift-version 5 \
  -target "$ARCH-apple-macos14.0" \
  -o build/tests \
  Sources/LRC.swift Sources/NotchPriority.swift Sources/PomodoroCore.swift Sources/PrayerTimesCore.swift Sources/Localization.swift Sources/LastFMCore.swift Tests/*.swift
./build/tests
