#!/usr/bin/env bash
# Capture App Store screenshots for KeyNest on iPhone 6.9" and iPad 13"
# simulators by driving the app through `KeyNestUITests / AppStoreScreenshots`.
#
# Pipeline (per device):
#   1. xcodebuild test                       — runs AppStoreScreenshots, which
#                                              calls DemoSeeder + saves
#                                              XCTAttachment screenshots.
#   2. xcrun xcresulttool export attachments — pulls PNGs + manifest.json out
#                                              of the .xcresult bundle (Xcode
#                                              ships this; no brew needed).
#   3. rename                                — maps the manifest's
#                                              `suggested_human_readable_name`
#                                              (the `attachment.name` we set
#                                              in the test) to a flat
#                                              `iphone-01-list.png`.
#
# Output: build/Screenshots/{iphone,ipad}/*.png
#
# Requirements: Xcode 26 with iOS 26 simulators installed.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="KeyNest.xcodeproj"
SCHEME="KeyNest"
TEST_PLAN_ARG="-only-testing:KeyNestUITests/AppStoreScreenshots"
DERIVED="build/DerivedData"
OUT="build/Screenshots"

# App Store sizes:
#   - iPhone 6.9" tier — iPhone 17 Pro Max (1320×2868). Accepted as 6.9".
#   - iPad 13"  tier — iPad Pro 13-inch (M4) (2064×2752).
IPHONE_NAME="iPhone 17 Pro Max"
IPAD_NAME="iPad Pro 13-inch (M4)"

rm -rf "$OUT"
mkdir -p "$OUT/iphone" "$OUT/ipad"

# Pulls every attachment from the xcresult, then walks manifest.json to find
# the original `attachment.name` (slug like "01-list") for each exported file.
# Requires python3, which ships with macOS.
extract_attachments() {
  local result_bundle="$1"
  local out_dir="$2"
  local prefix="$3"

  local raw="$(mktemp -d)"
  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$raw" >/dev/null

  python3 - "$raw" "$out_dir" "$prefix" <<'PY'
import json, os, re, shutil, sys
raw, out_dir, prefix = sys.argv[1:4]
with open(os.path.join(raw, "manifest.json")) as f:
    manifest = json.load(f)

# Match the leading slug we set via attachment.name in the test,
# e.g. "01-list_0_<uuid>.png" → slug "01-list".
SLUG_RE = re.compile(r"^([0-9]{2}-[a-z]+)")

count = 0
def walk(node):
    global count
    if isinstance(node, dict):
        for a in node.get("attachments") or []:
            name = a.get("suggestedHumanReadableName") or ""
            exported = a.get("exportedFileName")
            if not exported:
                continue
            m = SLUG_RE.match(name)
            if not m:
                continue
            src = os.path.join(raw, exported)
            if not os.path.exists(src):
                continue
            dst = os.path.join(out_dir, f"{prefix}-{m.group(1)}.png")
            shutil.copy(src, dst)
            count += 1
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)

walk(manifest)
print(f"  wrote {count} attachment(s)")
PY

  rm -rf "$raw"
}

run_one() {
  local device_name="$1"
  local out_dir="$2"
  local prefix="$3"

  echo "==> booting '$device_name' and pinning status bar to 9:41"
  # Boot the simulator if not already, so we can apply the status-bar override.
  # `simctl boot` is a no-op if already booted.
  xcrun simctl boot "$device_name" >/dev/null 2>&1 || true
  # Pin the status bar to the Apple-marketing 9:41 with full battery + signal.
  # The override persists for as long as the simulator stays booted; runs
  # before xcodebuild test below so the captured screenshots show the override.
  xcrun simctl status_bar "$device_name" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiBars 3 \
    --cellularBars 4 \
    --cellularMode active >/dev/null 2>&1 || true

  echo "==> running UI test on '$device_name'"
  local result_bundle="$DERIVED/$prefix.xcresult"
  rm -rf "$result_bundle"

  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$device_name" \
    -derivedDataPath "$DERIVED" \
    -resultBundlePath "$result_bundle" \
    $TEST_PLAN_ARG \
    -quiet

  echo "==> extracting attachments from $result_bundle"
  extract_attachments "$result_bundle" "$out_dir" "$prefix"
}

run_one "$IPHONE_NAME" "$OUT/iphone" "iphone"
run_one "$IPAD_NAME"   "$OUT/ipad"   "ipad"

# App Store Connect's iPhone slot in some configurations only accepts the
# legacy 6.7" sizes (1284x2778). Downsample the iPhone shots to that exact
# canvas for upload, alongside the originals.
echo "==> resizing iPhone shots → 1284x2778 for App Store upload"
mkdir -p "$OUT/iphone-appstore"
for f in "$OUT"/iphone/*.png; do
  out="$OUT/iphone-appstore/$(basename "$f")"
  sips --resampleHeightWidth 2778 1284 "$f" --out "$out" >/dev/null
done

echo ""
echo "Done."
echo "  iPhone shots (native 1320x2868): $OUT/iphone"
echo "  iPhone shots (App Store 1284x2778): $OUT/iphone-appstore  ← upload these"
echo "  iPad shots:   $OUT/ipad"
echo ""
echo "App Store Connect expects:"
echo "  iPhone 6.7\": 1284x2778 (use iphone-appstore/)"
echo "  iPad 13\":    2064x2752"
