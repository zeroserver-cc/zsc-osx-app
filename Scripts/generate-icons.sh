#!/bin/sh
# Regenerates every derived icon asset (app .icns + menu bar template PNGs)
# from the raw brand PNGs in BrandAssets/RawIcons/. Those raw files were
# downloaded once from https://zeroserver.cc/icons/icon-{192,512}.png and
# icon-maskable-512.png and committed as-is — this script never fetches
# anything over the network itself.
#
# Run this again only if the brand mark changes. Everything it produces is
# regenerated deterministically from RawIcons/icon-512.png, so there's no
# hand-editing of the generated files.
set -eu

cd "$(dirname "$0")/.."

RAW="BrandAssets/RawIcons/icon-512.png"
ICONSET="BrandAssets/AppIcon.iconset"
ICNS="BrandAssets/AppIcon.icns"
MENUBAR_DIR="Sources/ZeroServerControl/Resources/MenuBarIcon"
LOGO_DIR="Sources/ZeroServerControl/Resources/Logo"

command -v magick >/dev/null 2>&1 || { echo "error: ImageMagick (magick) is required" >&2; exit 1; }
command -v sips >/dev/null 2>&1 || { echo "error: sips is required (should ship with macOS)" >&2; exit 1; }
command -v iconutil >/dev/null 2>&1 || { echo "error: iconutil is required (should ship with macOS)" >&2; exit 1; }
[ -f "$RAW" ] || { echo "error: $RAW not found" >&2; exit 1; }

echo "==> Building app icon (.icns) from $RAW"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Standard 10-file iconset that `iconutil` expects. The app icon keeps the
# full-color green/black brand mark as-is (only the menu bar glyph below
# needs to become monochrome).
sips -z 16 16     "$RAW" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$RAW" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$RAW" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$RAW" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$RAW" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$RAW" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$RAW" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$RAW" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
cp                "$RAW"        "$ICONSET/icon_512x512.png"
# Source art is only 512x512, so this one slot is upscaled 512->1024. Softer
# than a true 1024 master, but this only ever shows at About-panel/Finder
# sizes for a menu bar utility, so it's an accepted tradeoff, not a bug.
sips -z 1024 1024 "$RAW" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "    -> $ICNS"

echo "==> Building menu bar template icon (chroma-keying #00FF41 to transparent)"
mkdir -p "$MENUBAR_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Step 1: cut out the brand green background (plus its anti-aliased edge
# fringe, hence -fuzz) leaving the black glyph on transparency.
magick "$RAW" -fuzz 12% -transparent "#00FF41" "$TMP/glyph-alpha.png"

# Step 2: throw away all color information and keep ONLY the shape, as a
# clean binary alpha mask. This matters because NSImage's `isTemplate`
# rendering uses the alpha channel as a stencil - any leftover
# semi-transparent green-tinted fringe pixels from step 1 would otherwise
# show up as a faint color halo once AppKit recolors the "black" pixels.
magick "$TMP/glyph-alpha.png" -alpha extract -threshold 50% "$TMP/glyph-mask.png"
magick -size 512x512 xc:black "$TMP/glyph-mask.png" -alpha off -compose CopyOpacity -composite \
    "$TMP/glyph-on-master.png"

# Step 3: downscale to Apple's ~18pt logical size for status-bar icons
# (18px @1x, 36px @2x).
sips -z 18 18 "$TMP/glyph-on-master.png" --out "$MENUBAR_DIR/MenuBarIcon-On.png"    >/dev/null
sips -z 36 36 "$TMP/glyph-on-master.png" --out "$MENUBAR_DIR/MenuBarIcon-On@2x.png" >/dev/null

# Step 4: derive the "Off" (stopped/dimmed) variant purely by reducing the
# alpha channel of the "On" variant - no new source art needed, since we
# only have the one solid brand glyph.
magick "$MENUBAR_DIR/MenuBarIcon-On.png"    -channel A -evaluate multiply 0.35 +channel "$MENUBAR_DIR/MenuBarIcon-Off.png"
magick "$MENUBAR_DIR/MenuBarIcon-On@2x.png" -channel A -evaluate multiply 0.35 +channel "$MENUBAR_DIR/MenuBarIcon-Off@2x.png"

echo "    -> $MENUBAR_DIR/MenuBarIcon-{On,Off}[@2x].png"

echo "==> Building full-color menu bar icon variant (bright green + black glyph, no chroma-key)"
# Alternative to the monochrome template pair above - see
# MenuBarIconProvider.swift's useMonochromeTemplateIcon flag for how the app
# picks between them. Background kept (unlike the chroma-keyed template
# icon), but cropped to a circle first - the raw square art has generous
# margin around the glyph (see BrandAssets/RawIcons/icon-512.png), so an
# inscribed circle (touching all four edges) crops only the square's
# corners, never the glyph itself.
magick -size 512x512 xc:none -antialias -fill white -draw "circle 256,256 256,0" "$TMP/circle-mask.png"
magick "$RAW" "$TMP/circle-mask.png" -alpha off -compose CopyOpacity -composite "$TMP/color-circular-master.png"

# Downscale with ImageMagick itself (Lanczos), not `sips -z` - at a ~28x
# reduction (512 -> 18px), sips's resampler doesn't filter the circle's hard
# alpha edge cleanly, leaving a visibly jagged/aliased boundary at such a
# tiny icon size. Lanczos filters properly on a large reduction ratio,
# producing a smooth, anti-aliased circular edge instead.
magick "$TMP/color-circular-master.png" -filter Lanczos -resize 18x18 "$MENUBAR_DIR/MenuBarIcon-On-Color.png"
magick "$TMP/color-circular-master.png" -filter Lanczos -resize 36x36 "$MENUBAR_DIR/MenuBarIcon-On-Color@2x.png"

# "Off" variant: same alpha-reduction technique as the monochrome pair - here
# it fades the whole glyph (background included) rather than just a shape.
magick "$MENUBAR_DIR/MenuBarIcon-On-Color.png"    -channel A -evaluate multiply 0.35 +channel "$MENUBAR_DIR/MenuBarIcon-Off-Color.png"
magick "$MENUBAR_DIR/MenuBarIcon-On-Color@2x.png" -channel A -evaluate multiply 0.35 +channel "$MENUBAR_DIR/MenuBarIcon-Off-Color@2x.png"

echo "    -> $MENUBAR_DIR/MenuBarIcon-{On,Off}-Color[@2x].png"

echo "==> Building login window logo (full color, unlike the monochrome menu bar glyph)"
mkdir -p "$LOGO_DIR"
sips -z 64 64   "$RAW" --out "$LOGO_DIR/AppLogo.png"    >/dev/null
sips -z 128 128 "$RAW" --out "$LOGO_DIR/AppLogo@2x.png" >/dev/null
echo "    -> $LOGO_DIR/AppLogo[@2x].png"

echo "Done."
