#!/usr/bin/env bash
# Build the iOS AppIcon from the Android adaptive-icon vector drawables.
#
# Pipeline: VectorDrawable XML → SVG → 1024×1024 PNG. The Android Adaptive
# Icon canvas is 108dp where the safe zone is the inner 66dp circle; iOS
# does not crop, so we render the full 108dp box and accept the "edge"
# elements (paper-nest curve) right at the bezel. iOS automatically rounds
# the corners — the 1024×1024 source must be a full square with no alpha.
#
# Requires: rsvg-convert (brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert missing — brew install librsvg" >&2
  exit 1
fi

ANDROID=../KeyNest/app/src/main/res/drawable
OUT_DIR=KeyNest/Resources/Assets.xcassets/AppIcon.appiconset
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) Background — blue linear gradient. Rebuild as plain SVG (the
#    aapt:attr gradient form would need a custom parser).
cat > "$TMP/bg.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 108 108">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="108" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#2E80F8"/>
      <stop offset="1" stop-color="#0F4AA8"/>
    </linearGradient>
  </defs>
  <rect width="108" height="108" fill="url(#bg)"/>
</svg>
SVG

# 2) Foreground — paper-nest shelter + K-key (rings + shaft + teeth).
#    Direct port from ic_launcher_foreground.xml.
cat > "$TMP/fg.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 108 108">
  <!-- Paper-nest shelter (cream) under the K -->
  <path d="M12.96,90.72 Q54,65.88 95.04,90.72 Z" fill="#F4EBDC" fill-opacity="0.95"/>
  <!-- K-key: bow (ring) -->
  <circle cx="32.4" cy="54" r="11.88" fill="none" stroke="#F4EBDC" stroke-width="7.56"/>
  <!-- K-key: shaft -->
  <line x1="44.28" y1="54" x2="90.72" y2="54" stroke="#F4EBDC" stroke-width="10.8" stroke-linecap="round"/>
  <!-- K-key: teeth -->
  <line x1="74.52" y1="54" x2="74.52" y2="71.28" stroke="#F4EBDC" stroke-width="7.56" stroke-linecap="round"/>
  <line x1="85.32" y1="54" x2="85.32" y2="65.88" stroke="#F4EBDC" stroke-width="7.56" stroke-linecap="round"/>
  <!-- Bow centerpoint (brand blue dot) -->
  <circle cx="32.4" cy="54" r="3.24" fill="#1F6FEB"/>
</svg>
SVG

# 3) Rasterize both layers and composite using rsvg-convert + librsvg
#    "use href" inline trick. Simplest robust path: render each into a PNG
#    then composite with Core Image via `sips` — but sips can't alpha-blend
#    layers. Use a third SVG that <image>-embeds both rasters.
rsvg-convert -w 1024 -h 1024 "$TMP/bg.svg" -o "$TMP/bg.png"
rsvg-convert -w 1024 -h 1024 "$TMP/fg.svg" -o "$TMP/fg.png"

# Encode as base64 inside one composed SVG so a single rsvg-convert call
# flattens both layers (bg first, fg on top) into the final PNG.
BG64=$(base64 -i "$TMP/bg.png")
FG64=$(base64 -i "$TMP/fg.png")
cat > "$TMP/combined.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="1024">
  <image width="1024" height="1024" xlink:href="data:image/png;base64,${BG64}"/>
  <image width="1024" height="1024" xlink:href="data:image/png;base64,${FG64}"/>
</svg>
SVG

mkdir -p "$OUT_DIR"
rsvg-convert -w 1024 -h 1024 "$TMP/combined.svg" -o "$OUT_DIR/AppIcon-1024.png"
echo "wrote $OUT_DIR/AppIcon-1024.png"
