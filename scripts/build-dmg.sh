#!/bin/bash
set -euo pipefail

APP_NAME="porthole-cmux"
VERSION="${1:-dev}"
BUILD_DIR="build"
DMG_DIR="${BUILD_DIR}/dmg"
APP_PATH="${DMG_DIR}/${APP_NAME}.app"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# Build libghostty
echo "Building libghostty..."
cd ghostty && zig build -Doptimize=ReleaseFast && cd ..

# Build Swift app (release)
echo "Building Swift app..."
xcodebuild -project GhosttyTabs.xcodeproj \
    -scheme cmux \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/derived" \
    -archivePath "${BUILD_DIR}/${APP_NAME}.xcarchive" \
    archive

# Extract app from archive
mkdir -p "${DMG_DIR}"
cp -R "${BUILD_DIR}/${APP_NAME}.xcarchive/Products/Applications/"*.app "${APP_PATH}"

# Copy panel resources
echo "Copying panel resources..."
mkdir -p "${APP_PATH}/Contents/Resources/panels"
cp -R Resources/panels/gitlab "${APP_PATH}/Contents/Resources/panels/"
cp -R Resources/panels/kanban "${APP_PATH}/Contents/Resources/panels/"

# Ad-hoc sign
echo "Signing..."
codesign --force --deep --sign - "${APP_PATH}"

# Create DMG
echo "Creating DMG..."
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

echo "=== Done: ${DMG_PATH} ==="
ls -lh "${DMG_PATH}"
