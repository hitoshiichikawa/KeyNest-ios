#!/usr/bin/env bash
# Build an App Store distribution archive and export the IPA.
#
# Pipeline:
#   1. xcodegen generate                        — refresh project from project.yml
#   2. xcodebuild archive                       — Release config, generic iOS device
#   3. xcodebuild -exportArchive                — App Store-style IPA via
#                                                 ExportOptions.plist
#
# Output: build/Archive/KeyNest.xcarchive + build/Export/KeyNest.ipa
#
# Requires Local.xcconfig to set DEVELOPMENT_TEAM (already required for
# device debug builds). The IPA can then be:
#   - Uploaded to App Store Connect with Transporter or `xcrun altool`.
#   - Validated locally with `xcrun altool --validate-app -f <ipa> -t ios`.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen missing — brew install xcodegen" >&2
  exit 1
fi
if [[ ! -f Local.xcconfig ]]; then
  echo "error: Local.xcconfig missing — copy Local.xcconfig.example and fill in DEVELOPMENT_TEAM" >&2
  exit 1
fi

# Resolve DEVELOPMENT_TEAM from xcconfig (single line "KEY = VALUE").
DEV_TEAM=$(grep -E '^DEVELOPMENT_TEAM' Local.xcconfig | awk -F= '{gsub(/ /,"",$2); print $2}')
if [[ -z "$DEV_TEAM" ]]; then
  echo "error: DEVELOPMENT_TEAM not found in Local.xcconfig" >&2
  exit 1
fi

OUT_DIR="build"
ARCHIVE_PATH="$OUT_DIR/Archive/KeyNest.xcarchive"
EXPORT_DIR="$OUT_DIR/Export"
EXPORT_OPTS_SRC="scripts/ExportOptions.plist"
EXPORT_OPTS="$OUT_DIR/ExportOptions.plist"

mkdir -p "$OUT_DIR"

echo "==> xcodegen generate"
xcodegen generate

echo "==> resolving ExportOptions.plist with DEVELOPMENT_TEAM=$DEV_TEAM"
# Substitute the $(DEVELOPMENT_TEAM) placeholder in a copy so the committed
# template stays portable.
sed "s/\$(DEVELOPMENT_TEAM)/$DEV_TEAM/g" "$EXPORT_OPTS_SRC" > "$EXPORT_OPTS"

echo "==> xcodebuild archive (Release, generic iOS device)"
xcodebuild archive \
  -project KeyNest.xcodeproj \
  -scheme KeyNest \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates

echo "==> xcodebuild -exportArchive (App Store IPA)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -allowProvisioningUpdates

echo ""
echo "Done."
echo "  archive: $ARCHIVE_PATH"
echo "  ipa:     $EXPORT_DIR/KeyNest.ipa"
echo ""
echo "Next steps:"
echo "  - Validate:  xcrun altool --validate-app -f $EXPORT_DIR/KeyNest.ipa -t ios --apiKey <key> --apiIssuer <issuer>"
echo "  - Upload:    open -a Transporter $EXPORT_DIR/KeyNest.ipa"
echo "             OR"
echo "             xcrun altool --upload-app -f $EXPORT_DIR/KeyNest.ipa -t ios --apiKey <key> --apiIssuer <issuer>"
