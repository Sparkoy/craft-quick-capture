#!/usr/bin/env bash
# build.sh — build CraftQuickCapture via Swift Package Manager
# Usage:
#   ./build.sh           → builds .build/bundle/CraftQuickCapture.app
#   ./build.sh --install → builds, installs to /Applications, relaunches

set -euo pipefail

APP_NAME="CraftQuickCapture"
BUNDLE_ID="com.pribat.craftquickcapture"
BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/bundle"
BINARY_SRC=".build/release/${APP_NAME}"
PLIST_SRC="Resources/Info.plist"

echo "▶ Building ${APP_NAME}…"
swift build -c release 2>&1 | grep -v "^Build complete" || true
swift build -c release --quiet

echo "▶ Assembling .app bundle…"
rm -rf "${BUILD_DIR}/${BUNDLE}"
mkdir -p "${BUILD_DIR}/${BUNDLE}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${BUNDLE}/Contents/Resources"

cp "${BINARY_SRC}" "${BUILD_DIR}/${BUNDLE}/Contents/MacOS/${APP_NAME}"

# Generate Info.plist if Resources/Info.plist exists, else write inline
if [[ -f "${PLIST_SRC}" ]]; then
    cp "${PLIST_SRC}" "${BUILD_DIR}/${BUNDLE}/Contents/Info.plist"
else
    cat > "${BUILD_DIR}/${BUNDLE}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
fi

# Ad-hoc code sign (no Developer ID required for local use)
echo "▶ Signing (ad-hoc)…"
codesign --force --sign - --entitlements /dev/null \
    "${BUILD_DIR}/${BUNDLE}" 2>/dev/null || \
codesign --force --sign - "${BUILD_DIR}/${BUNDLE}"

if [[ "${1:-}" == "--install" ]]; then
    echo "▶ Installing to /Applications…"
    # Kill running instance gracefully
    pkill -x "${APP_NAME}" 2>/dev/null || true
    sleep 0.3
    rm -rf "/Applications/${BUNDLE}"
    cp -r "${BUILD_DIR}/${BUNDLE}" "/Applications/"
    sleep 0.2
    open "/Applications/${BUNDLE}"
    echo "✓ ${APP_NAME} installed and launched"
else
    echo "✓ Built: ${BUILD_DIR}/${BUNDLE}"
fi
