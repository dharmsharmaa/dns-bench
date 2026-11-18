#!/bin/zsh
#
# DNS Bench — build a self-contained macOS .app from the local Electron dist.
#
#   1. sanity-check the toolchain
#   2. npm install on first run (electron + devDependencies)
#   3. render the app / tray icons (scripts/make-icon.js)
#   4. icon.png -> build/icon.iconset -> build/icon.icns
#   5. copy Electron.app -> ../releases/DNS Bench.app, swap in the app payload,
#      rewrite Info.plist and ad-hoc sign the bundle
#
# No @electron/packager, no network access beyond the first npm install.
# Idempotent: every run re-creates build/icon.* and ../releases/DNS Bench.app.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd -- "$ROOT/.." && pwd -P)"

APP_SRC="$ROOT/app"
BUILD_DIR="$ROOT/build"
DIST_DIR="$REPO_ROOT/releases"
BUNDLE="$DIST_DIR/DNS Bench.app"
ICONSET="$BUILD_DIR/icon.iconset"
ICNS="$BUILD_DIR/icon.icns"

EXECUTABLE="DNS Bench"
BUNDLE_ID="com.dharmsharma.dnsbench"
SHORT_VERSION="1.0.0"
BUNDLE_VERSION="1.0.0"
MIN_MACOS="12.0"
COPYRIGHT="© 2026 Dharm Sharma · MIT"

PLIST_BUDDY=/usr/libexec/PlistBuddy

step() { printf '\033[36m▸\033[0m %s\n' "$*" }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2 }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1 }

# --------------------------------------------------------------------------
# toolchain
# --------------------------------------------------------------------------
step "checking toolchain"

for tool in node npm; do
  command -v "$tool" >/dev/null 2>&1 \
    || die "'$tool' not found in PATH — install Node.js 18+ from https://nodejs.org and retry"
done

for tool in /usr/bin/sips /usr/bin/iconutil /usr/bin/codesign /usr/bin/plutil; do
  [[ -x "$tool" ]] \
    || die "$tool is missing — install the macOS Command Line Tools: xcode-select --install"
done

[[ -x "$PLIST_BUDDY" ]] \
  || die "$PLIST_BUDDY is missing — the macOS developer tools are incomplete (xcode-select --install)"

command -v rsync >/dev/null 2>&1 \
  || die "rsync is missing — it normally ships with macOS (/usr/bin/rsync)"

node_major="$(node -p 'process.versions.node.split(".")[0]')"
(( node_major >= 18 )) || die "Node 18 or newer is required (found $(node -v))"

# --------------------------------------------------------------------------
# dependencies
# --------------------------------------------------------------------------
cd "$APP_SRC"

if [[ ! -d node_modules/electron ]]; then
  step "installing dependencies (first run, this can take a minute)"
  npm install --no-audit --no-fund
fi

ELECTRON_APP="$APP_SRC/node_modules/electron/dist/Electron.app"
[[ -d "$ELECTRON_APP" ]] \
  || die "Electron.app not found at $ELECTRON_APP — remove app/node_modules and rerun"

# --------------------------------------------------------------------------
# icons
# --------------------------------------------------------------------------
step "rendering icons"
node "$ROOT/scripts/make-icon.js"

step "building icon.icns"
rm -rf "$ICONSET" "$ICNS"
mkdir -p "$ICONSET"

SOURCE_ICON="$APP_SRC/resources/icon.png"
[[ -f "$SOURCE_ICON" ]] || die "missing $SOURCE_ICON"

# iconutil only accepts this exact naming scheme (logical size + @2x variant).
resize() {
  local name="$1" px="$2"
  /usr/bin/sips -z "$px" "$px" "$SOURCE_ICON" --out "$ICONSET/$name" >/dev/null 2>&1 \
    || die "sips failed while generating $name (${px}px)"
}

resize icon_16x16.png 16
resize icon_16x16@2x.png 32
resize icon_32x32.png 32
resize icon_32x32@2x.png 64
resize icon_128x128.png 128
resize icon_128x128@2x.png 256
resize icon_256x256.png 256
resize icon_256x256@2x.png 512
resize icon_512x512.png 512
resize icon_512x512@2x.png 1024

/usr/bin/iconutil --convert icns "$ICONSET" --output "$ICNS" \
  || die "iconutil failed to build $ICNS"
[[ -f "$ICNS" ]] || die "iconutil did not produce $ICNS"

# --------------------------------------------------------------------------
# bundle skeleton
# --------------------------------------------------------------------------
step "packaging DNS Bench.app"
rm -rf "$BUNDLE"
mkdir -p "$DIST_DIR"
cp -R "$ELECTRON_APP" "$BUNDLE"

mv "$BUNDLE/Contents/MacOS/Electron" "$BUNDLE/Contents/MacOS/$EXECUTABLE"
rm -f "$BUNDLE/Contents/Resources/default_app.asar"

PAYLOAD="$BUNDLE/Contents/Resources/app"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
rsync -a --delete \
  --exclude 'node_modules' \
  --exclude 'build' \
  --exclude 'dist' \
  --exclude '.DS_Store' \
  --exclude 'results' \
  --exclude 'history.json' \
  "$APP_SRC/" "$PAYLOAD/"

[[ -f "$PAYLOAD/package.json" ]] || die "app payload is missing package.json"
[[ -f "$PAYLOAD/main.js" ]] || die "app payload is missing main.js"

cp "$ICNS" "$BUNDLE/Contents/Resources/icon.icns"

# --------------------------------------------------------------------------
# Info.plist
# --------------------------------------------------------------------------
step "writing Info.plist"
PLIST="$BUNDLE/Contents/Info.plist"
[[ -f "$PLIST" ]] || die "the Electron bundle has no Info.plist"

# Delete + Add keeps the value type unambiguous on every rerun.
plist_set_string() {
  local key="$1" value="$2"
  "$PLIST_BUDDY" -c "Delete :$key" "$PLIST" >/dev/null 2>&1 || true
  "$PLIST_BUDDY" -c "Add :$key string $value" "$PLIST" >/dev/null \
    || die "PlistBuddy could not set $key"
}

plist_set_bool() {
  local key="$1" value="$2"
  "$PLIST_BUDDY" -c "Delete :$key" "$PLIST" >/dev/null 2>&1 || true
  "$PLIST_BUDDY" -c "Add :$key bool $value" "$PLIST" >/dev/null \
    || die "PlistBuddy could not set $key"
}

plist_set_string CFBundleName "DNS Bench"
plist_set_string CFBundleDisplayName "DNS Bench"
plist_set_string CFBundleExecutable "$EXECUTABLE"
plist_set_string CFBundleIdentifier "$BUNDLE_ID"
plist_set_string CFBundleShortVersionString "$SHORT_VERSION"
plist_set_string CFBundleVersion "$BUNDLE_VERSION"
plist_set_string CFBundleIconFile "icon"
plist_set_bool   NSHighResolutionCapable true
plist_set_string LSMinimumSystemVersion "$MIN_MACOS"
plist_set_string NSHumanReadableCopyright "$COPYRIGHT"
plist_set_string CFBundleDevelopmentRegion "en"

/usr/bin/plutil -lint "$PLIST" >/dev/null || die "Info.plist failed validation"

# --------------------------------------------------------------------------
# ad-hoc signature
# --------------------------------------------------------------------------
step "ad-hoc signing (this signs every nested helper)"
/usr/bin/codesign --force --deep --sign - "$BUNDLE" 2>&1 | sed 's/^/    /' \
  || die "codesign failed"

/usr/bin/codesign --verify --deep --strict "$BUNDLE" \
  || die "signature verification failed"

step "verifying bundle"
/usr/bin/codesign -dv "$BUNDLE" 2>&1 | sed -n '1,6p' | sed 's/^/    /'
/usr/bin/plutil -lint "$PLIST" | sed 's/^/    /'

SIZE="$(du -sh "$BUNDLE" | awk '{print $1}')"

printf '\n\033[32m✓\033[0m DNS Bench.app is ready\n'
printf '    bundle   %s\n' "$BUNDLE"
printf '    size     %s\n' "$SIZE"
printf '    version  %s (%s)\n' "$SHORT_VERSION" "$BUNDLE_VERSION"
printf '    id       %s\n' "$BUNDLE_ID"
printf '\n    open "%s"\n\n' "$BUNDLE"
