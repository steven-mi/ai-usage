#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP="$ROOT/dist/AI Usage.app"
BUILT_EXECUTABLE="$ROOT/dist/AIUsage.new"
WAS_RUNNING=0
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist"

swiftc -O -parse-as-library -target arm64-apple-macosx13.0 "$ROOT/UsageBar.swift" \
  -module-cache-path "${TMPDIR:-/tmp}/codex-claude-usage-module-cache" \
  -framework SwiftUI -framework AppKit -framework Combine -framework CryptoKit \
  -o "$BUILT_EXECUTABLE"

swift -module-cache-path "${TMPDIR:-/tmp}/ai-usage-icon-module-cache" \
  "$ROOT/IconGenerator.swift" "$ROOT/dist/AIUsage-master.png"

if /usr/bin/killall -s 0 AIUsage >/dev/null 2>&1; then
  WAS_RUNNING=1
  /usr/bin/killall AIUsage >/dev/null 2>&1 || true
  wait_count=0
  while /usr/bin/killall -s 0 AIUsage >/dev/null 2>&1 && [ "$wait_count" -lt 30 ]; do
    sleep 0.2
    wait_count=$((wait_count + 1))
  done
  if /usr/bin/killall -s 0 AIUsage >/dev/null 2>&1; then
    /usr/bin/killall -9 AIUsage >/dev/null 2>&1 || true
  fi
fi

mv -f "$BUILT_EXECUTABLE" "$APP/Contents/MacOS/AIUsage"
cp "$ROOT/dist/AIUsage-master.png" "$APP/Contents/Resources/AppIcon.png"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>AIUsage</string>
  <key>CFBundleIdentifier</key><string>com.aiusage.menu</string>
  <key>CFBundleIconFile</key><string>AppIcon.png</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>AI Usage</string>
  <key>CFBundleDisplayName</key><string>AI Usage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP" >/dev/null

echo "Built: $APP"
if [ "$WAS_RUNNING" -eq 1 ] || [ "${1:-}" = "--open" ]; then
  open "$APP"
fi
