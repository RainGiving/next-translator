#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: ./scripts/release.sh 1.0.1" >&2
  exit 1
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([.-][A-Za-z0-9]+)?$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PROJECT_FILE="project.yml"
CASK_FILE="packaging/homebrew/next-translator.rb"
SCHEME="NextTranslator"
APP_NAME="Next Translator.app"
DERIVED_DATA="build/release"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
DIST_DIR="dist"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/Next-Translator-$VERSION.dmg"
POPCLIP_STAGE="$DIST_DIR/next-translator.popclipext"
POPCLIP_ZIP="$DIST_DIR/next-translator.popclipextz"

sed -i '' -E "s/(MARKETING_VERSION: \")[^\"]+(\")/\\1$VERSION\\2/" "$PROJECT_FILE"

xcodegen generate
xcodebuild \
  -project NextTranslator.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build

rm -rf "$STAGING_DIR" "$POPCLIP_STAGE" "$DMG_PATH" "$POPCLIP_ZIP"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Next Translator" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

mkdir -p "$POPCLIP_STAGE"
cp -R clip-extensions/popclip/. "$POPCLIP_STAGE/"
(cd "$DIST_DIR" && zip -qry "next-translator.popclipextz" "next-translator.popclipext")

DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
sed -i '' -E "s/version \"[^\"]+\"/version \"$VERSION\"/" "$CASK_FILE"
sed -i '' -E "s/sha256 \"[^\"]+\"/sha256 \"$DMG_SHA256\"/" "$CASK_FILE"

cat <<EOF
Release artifacts:
  $DMG_PATH
  $POPCLIP_ZIP

Updated:
  $PROJECT_FILE MARKETING_VERSION -> $VERSION
  $CASK_FILE version -> $VERSION
  $CASK_FILE sha256 -> $DMG_SHA256

Manual next steps:
  git add $PROJECT_FILE $CASK_FILE scripts/release.sh
  git commit -m "chore: release $VERSION"
  git tag "v$VERSION"
  git push origin HEAD --tags
  gh release create "v$VERSION" "$DMG_PATH" "$POPCLIP_ZIP" --title "Next Translator $VERSION" --notes ""
  update the Homebrew tap with packaging/homebrew/next-translator.rb
EOF
