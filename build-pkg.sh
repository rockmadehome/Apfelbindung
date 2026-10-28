#!/bin/bash
set -euo pipefail

PROJECT="Apfelbindung.xcodeproj"
SCHEME="Apfelbindung"
CONFIG="Release"
APP_NAME="Apfelbindung"

VERSION="${MARKETING_VERSION_OVERRIDE:-$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
    | grep -m1 'MARKETING_VERSION' | awk '{print $3}')}"
BUILD_NUM=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
    | grep -m1 'CURRENT_PROJECT_VERSION' | awk '{print $3}')

if [ -z "$VERSION" ]; then
    echo "Error: Could not determine version from Xcode project" >&2
    exit 1
fi

PKG_NAME="Apfelbindung-${VERSION}.pkg"
echo "Building ${APP_NAME} v${VERSION} (${BUILD_NUM})..."

xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" clean build \
    MARKETING_VERSION="$VERSION" \
    BUILD_NUMBER="$BUILD_NUM"

BUILT=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
    | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')

if [ ! -d "${BUILT}/${APP_NAME}.app" ]; then
    echo "Error: ${APP_NAME}.app not found at ${BUILT}" >&2
    exit 1
fi

echo "Creating ${PKG_NAME}..."
productbuild --component "${BUILT}/${APP_NAME}.app" /Applications "$PKG_NAME"

echo "Done: $(pwd)/${PKG_NAME} ($(du -h "$PKG_NAME" | cut -f1))"
