#!/bin/bash
set -euo pipefail

BUNDLE_ID="com.pedro.QuickLookMarkdownApp"
EXTENSION_ID="${BUNDLE_ID}.QuickLookMarkdownPreviewExtension"
APP_NAME="QuickMD"
INSTALL_DIR="/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building..."
xcodebuild -scheme QuickLookMarkdownApp -configuration Debug \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  build 2>&1 | tail -3

# Find the built app in DerivedData
BUILD_DIR=$(xcodebuild -scheme QuickLookMarkdownApp -configuration Debug \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')
BUILT_APP="${BUILD_DIR}/${APP_NAME}.app"

if [ ! -d "$BUILT_APP" ]; then
  echo "ERROR: Built app not found at ${BUILT_APP}"
  exit 1
fi

echo "==> Installing to ${INSTALL_DIR}/${APP_NAME}.app..."
killall "$APP_NAME" 2>/dev/null || true
sleep 1
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "$BUILT_APP" "${INSTALL_DIR}/${APP_NAME}.app"

echo "==> Registering with LaunchServices..."
$LSREGISTER -f -R -trusted "${INSTALL_DIR}/${APP_NAME}.app"

echo "==> Enabling Quick Look extension..."
pluginkit -e use -i "$EXTENSION_ID"

echo "==> Setting as default handler for markdown, JSON, and YAML..."
swift -e '
import Foundation
import CoreServices
let types = ["net.daringfireball.markdown", "public.json", "public.yaml"]
for type in types {
    LSSetDefaultRoleHandlerForContentType(type as CFString, LSRolesMask.all, "'"$BUNDLE_ID"'" as CFString)
}
'

echo "==> Resetting Quick Look cache..."
qlmanage -r 2>&1 | head -1
qlmanage -r cache 2>&1 | head -1

echo ""
echo "Done! ${APP_NAME} installed to ${INSTALL_DIR}/${APP_NAME}.app"
echo "Select any .md, .json, .yaml, or source file in Finder and press Space."
