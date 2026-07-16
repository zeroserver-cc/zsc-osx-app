#!/bin/sh
# Assembles a real, double-clickable "ZeroServer Control.app" out of the
# Swift Package Manager release build. SPM alone only produces a bare
# executable - this script does the rest of what Xcode would normally do
# automatically: build the .app folder structure, drop in Info.plist and
# the app icon, carry over the SPM resource bundle (the menu bar icon
# PNGs), and ad-hoc code-sign the result.
#
# Usage:
#   Scripts/build-app-bundle.sh                # builds version 0.1.0 / build 1
#   VERSION=1.2.0 BUILD=7 Scripts/build-app-bundle.sh
#   CONFIGURATION=debug Scripts/build-app-bundle.sh
#
# CONFIGURATION=debug builds ".build/debug" (fast, incremental — same as
# `swift run`) instead of "-c release", into a separate "ZeroServer Control
# (Debug).app" so it can never be confused with or overwrite a real release
# build. This exists because window activation/foreground/key-window
# behavior is genuinely unreliable when run unbundled via `swift run` — an
# SPM executable started from a terminal has no CFBundleIdentifier and never
# goes through LaunchServices the way a real .app does, and macOS treats
# that as a lower-trust process for focus-stealing purposes (a deliberate
# OS security/UX behavior, not a bug in this app — confirmed by testing:
# the exact same window-focus code that misbehaves under `swift run` works
# correctly once packaged, even as an ad-hoc-signed debug build). Anything
# that involves opening Login/Settings/Dashboard and expecting normal
# window/keyboard-focus behavior should be tested via this debug bundle,
# not `swift run`.
set -eu

cd "$(dirname "$0")/.."

# 0.1.0, not 1.0.0 — this is still a beta (see CLAUDE.md); 1.0.0 is reserved
# for the first stable, feature-complete release.
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
EXECUTABLE_NAME="ZeroServerControl"
DIST_DIR="dist"

case "$CONFIGURATION" in
    release)
        BUILD_FLAGS="-c release"
        BUILD_DIR=".build/release"
        APP_NAME="ZeroServer Control"
        ;;
    debug)
        BUILD_FLAGS=""
        BUILD_DIR=".build/debug"
        APP_NAME="ZeroServer Control (Debug)"
        ;;
    *)
        echo "CONFIGURATION must be 'release' or 'debug' (got: $CONFIGURATION)" >&2
        exit 1
        ;;
esac
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "==> swift build $BUILD_FLAGS"
swift build $BUILD_FLAGS --product "$EXECUTABLE_NAME"

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    "Packaging/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"

cp "BrandAssets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Copy the menu bar icon PNGs straight into Contents/Resources/MenuBarIcon,
# as plain files - NOT via SPM's generated "*_ZeroServerControl.bundle"
# resource bundle. We deliberately don't reuse that generated bundle here:
# its accessor (.build/*/resource_bundle_accessor.swift) requires the bundle
# to sit at the .app's TOP LEVEL (via `Bundle.main.bundleURL`, which for a
# real .app is the .app folder itself, not Contents/Resources), and
# `codesign` refuses to seal a bundle with anything other than `Contents/`
# at that top level ("unsealed contents present in the bundle root") - that
# combination is exactly what made the app crash instantly and silently on
# double-click before this was fixed. Plain files under Contents/Resources
# are the standard, codesign-friendly location; MenuBarIconProvider looks
# there first (via Bundle.main) and only falls back to the SPM bundle
# mechanism when running unbundled via `swift run`.
mkdir -p "$APP_BUNDLE/Contents/Resources/MenuBarIcon"
cp Sources/ZeroServerControl/Resources/MenuBarIcon/*.png "$APP_BUNDLE/Contents/Resources/MenuBarIcon/"

# Same rationale, same plain-files-under-Contents/Resources approach, for the
# full-color login window logo (see AppLogoProvider.swift).
mkdir -p "$APP_BUNDLE/Contents/Resources/Logo"
cp Sources/ZeroServerControl/Resources/Logo/*.png "$APP_BUNDLE/Contents/Resources/Logo/"

# Localization (see Package.swift's .process("Resources/en.lproj") etc.):
# Text/NSLocalizedString both resolve against Bundle.main in a real .app, so
# the SAME "copy as plain files under Contents/Resources, don't rely on the
# generated SPM bundle" rationale above applies here too. Unlike the PNGs,
# these DO need an SPM build step first (.process() compiles the .strings
# files), so copy from the build output's resource bundle, not straight
# from Sources/ - and copy every *.lproj SPM produced there (its folder
# names may be lowercased, e.g. "pt-br.lproj" for "pt-BR" - copy verbatim
# rather than assuming a specific casing).
RESOURCE_BUNDLE="$BUILD_DIR/${EXECUTABLE_NAME}_${EXECUTABLE_NAME}.bundle"
for lproj in "$RESOURCE_BUNDLE"/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$APP_BUNDLE/Contents/Resources/"
done

echo "==> Ad-hoc code signing"
# Removes any quarantine/extended attributes that could interfere with
# signing, then signs with the special "-" identity, i.e. ad-hoc: no
# Developer ID needed. This mirrors zsc-agent-runner/install.sh's own
# rationale for ad-hoc signing on Apple Silicon (unsigned/mis-signed
# bundles can be killed at launch), and SMAppService (Launch at Login)
# requires at least a validly ad-hoc-signed bundle to register at all.
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo "First launch: right-click > Open (unsigned/ad-hoc apps aren't Gatekeeper-trusted by default)."
