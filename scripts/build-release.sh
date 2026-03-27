#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="DiskSpaceHelper"
BUILD_DIR="build"
RELEASE_DIR="release"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

echo "==> Building $APP_NAME v$VERSION..."

# Clean previous artifacts
rm -rf "$BUILD_DIR" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Generate Xcode project via Tuist (if available)
if command -v tuist &> /dev/null; then
    echo "==> Generating Xcode project with Tuist..."
    tuist generate --no-open
fi

# Build release binary (ad-hoc signed, no notarization)
xcodebuild -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | tail -5

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build failed — $APP_PATH not found"
    exit 1
fi

echo "==> Build succeeded: $APP_PATH"

# Create ZIP
echo "==> Creating ZIP..."
cd "$BUILD_DIR/Build/Products/Release"
zip -r -q "../../../../$RELEASE_DIR/$APP_NAME-$VERSION.zip" "$APP_NAME.app"
cd - > /dev/null
echo "    $RELEASE_DIR/$APP_NAME-$VERSION.zip"

# Create DMG
echo "==> Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$RELEASE_DIR/$APP_NAME-$VERSION.dmg" \
    -quiet

echo "    $RELEASE_DIR/$APP_NAME-$VERSION.dmg"

# Print SHA256 for Homebrew cask
echo ""
echo "==> SHA256 checksums:"
shasum -a 256 "$RELEASE_DIR/$APP_NAME-$VERSION.zip"
shasum -a 256 "$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

echo ""
echo "==> Done! Artifacts in $RELEASE_DIR/"
