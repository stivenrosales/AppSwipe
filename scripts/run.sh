#!/bin/bash

set -euo pipefail

# app-swipe: idempotent build, bundle, sign, and launch script
# Usage: ./scripts/run.sh

PROJECT_ROOT="/Users/stivenkevinrosalescasas/app-swipe"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
APP_NAME="AppSwipe"
# Install into /Applications so launchers (Raycast, Spotlight) index it and the user can open it
# by name. The stable code signature keeps the Accessibility permission across the move/rebuilds.
APP_BUNDLE="/Applications/${APP_NAME}.app"
BUNDLE_CONTENTS="${APP_BUNDLE}/Contents"
BUNDLE_MACOS="${BUNDLE_CONTENTS}/MacOS"
EXECUTABLE_PATH="${BUILD_DIR}/${APP_NAME}"
INFO_PLIST="${BUNDLE_CONTENTS}/Info.plist"

# Step 1: Build with Swift Package Manager (release configuration)
# NOTE: must go through `make release` (the swift-wrapper) because plain
# `swift build` cannot compile the Package manifest on macOS 26 Tahoe CLT.
echo "[1/5] Building ${APP_NAME} (release)..."
make -C "${PROJECT_ROOT}" release

if [ ! -f "${EXECUTABLE_PATH}" ]; then
  echo "Error: Executable not found at ${EXECUTABLE_PATH}"
  exit 1
fi

# Step 2: Remove old bundle and create directory structure
echo "[2/5] Preparing bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${BUNDLE_MACOS}"

# Step 3: Copy executable to MacOS folder
echo "[3/5] Copying executable..."
cp "${EXECUTABLE_PATH}" "${BUNDLE_MACOS}/${APP_NAME}"
chmod +x "${BUNDLE_MACOS}/${APP_NAME}"

# Step 4: Create Info.plist with required keys for agent app (LSUIElement=true)
echo "[4/5] Creating Info.plist..."
cat > "${INFO_PLIST}" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>AppSwipe</string>
	<key>CFBundleIdentifier</key>
	<string>com.appswipe.app</string>
	<key>CFBundleName</key>
	<string>AppSwipe</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
</dict>
</plist>
EOF

# Step 5: Code signing with a STABLE local identity so macOS keeps the granted
# Accessibility/Input-Monitoring permissions across rebuilds. Ad-hoc signing would
# change the cdhash every build and reset the permissions. See scripts/setup-signing.sh.
echo "[5/5] Signing bundle..."
"${PROJECT_ROOT}/scripts/setup-signing.sh" >/dev/null 2>&1 || true
SIGN_ID="AppSwipe Local Signing"
if codesign --force --deep --sign "${SIGN_ID}" "${APP_BUNDLE}" 2>/dev/null; then
  echo "    signed with stable identity: ${SIGN_ID}"
else
  echo "    stable identity unavailable; using ad-hoc (permissions will reset each build)"
  codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
fi

# Step 6: Launch the app
echo "[✓] Build complete. Launching ${APP_NAME}..."
open "${APP_BUNDLE}"
