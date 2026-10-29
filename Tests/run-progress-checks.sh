#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
CHECKS_DIR=$(mktemp -d "${TMPDIR:-/tmp/}lulexia-checks.XXXXXX")
trap 'rm -rf "$CHECKS_DIR"' EXIT
xcrun swiftc -module-cache-path "$CHECKS_DIR/cache" Lulexia/Gamification.swift Tests/GamificationChecks.swift -o "$CHECKS_DIR/rules"
"$CHECKS_DIR/rules"
BUNDLE_DIR="$CHECKS_DIR/LulexiaProgressChecks.app/Contents"
mkdir -p "$BUNDLE_DIR/MacOS"
xcrun swiftc -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$CHECKS_DIR/cache" Lulexia/Gamification.swift Lulexia/ProgressStore.swift Tests/ProgressPersistenceChecks.swift -o "$BUNDLE_DIR/MacOS/LulexiaProgressChecks"
cat > "$BUNDLE_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.lulexia.progress-checks</string>
<key>CFBundleName</key><string>LulexiaProgressChecks</string>
<key>CFBundleExecutable</key><string>LulexiaProgressChecks</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
"$BUNDLE_DIR/MacOS/LulexiaProgressChecks"
