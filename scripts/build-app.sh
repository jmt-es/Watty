#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

URL_SCHEME="watty"
MINIMUM_SYSTEM_VERSION="13.0"
DEVELOPMENT_LANGUAGE="en"
COPYRIGHT="© 2026 Javier Martinez Tornero. Released under the MIT License."
ICON_NAME="WattyIcon"
ICON_SOURCE="$ROOT_DIR/Assets/WattyIconSource.png"
ICON_SIZES=(16 32 128 256 512)
LOCALIZATION_DIR="$ROOT_DIR/Localization"
PRODUCTS=("$APP_EXECUTABLE" "$CLI_PRODUCT")
OUTPUT_DIR="$ROOT_DIR/build"
SWIFT_FLAGS=()
LOCALIZATIONS=()
WORK_DIR=""

usage() {
  cat <<USAGE
Usage: scripts/build-app.sh [--output-dir DIR] [SWIFT_BUILD_FLAGS...]

Builds the release products with SwiftPM and assembles $APP_NAME.app, with the
$CLI_PRODUCT command embedded, into DIR. The bundle is ad-hoc signed.

  --output-dir DIR   where $APP_NAME.app is created (default: build)
  -h, --help         show this help

Every other argument is passed to each 'swift build' call, for example
--disable-sandbox (Homebrew), --arch arm64 --arch x86_64 or --scratch-path DIR.
USAGE
}

cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output-dir)
        [[ $# -ge 2 ]] || die "--output-dir needs a directory"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        SWIFT_FLAGS+=("$@")
        break
        ;;
      *)
        SWIFT_FLAGS+=("$1")
        shift
        ;;
    esac
  done
}

discover_localizations() {
  local lproj language
  LOCALIZATIONS=("$DEVELOPMENT_LANGUAGE")
  for lproj in "$LOCALIZATION_DIR"/*.lproj; do
    [[ -d "$lproj" ]] || continue
    language="$(basename "$lproj" .lproj)"
    [[ "$language" == "$DEVELOPMENT_LANGUAGE" || "$language" == "Base" ]] || LOCALIZATIONS+=("$language")
  done
}

swift_build() {
  swift build --package-path "$ROOT_DIR" -c release "$@" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
}

build_products() {
  local product
  for product in "${PRODUCTS[@]}"; do
    log "Building $product ($APP_VERSION, build $APP_BUILD)"
    swift_build --product "$product"
  done
}

generate_icon() {
  local destination="$1" iconset="$WORK_DIR/$ICON_NAME.iconset" size
  mkdir -p "$iconset"
  for size in "${ICON_SIZES[@]}"; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$ICON_SOURCE" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$destination"
}

write_info_plist() {
  local destination="$1" language localizations=""
  for language in "${LOCALIZATIONS[@]}"; do
    localizations+="        <string>$language</string>"$'\n'
  done
  cat >"$destination" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$DEVELOPMENT_LANGUAGE</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_EXECUTABLE</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
${localizations%$'\n'}
    </array>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>$URL_SCHEME</string>
            </array>
        </dict>
    </array>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MINIMUM_SYSTEM_VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>$COPYRIGHT</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
  plutil -lint "$destination" >/dev/null || die "Generated an invalid Info.plist"
}

copy_localizations() {
  local resources_dir="$1" lproj strings_file
  for lproj in "$LOCALIZATION_DIR"/*.lproj; do
    [[ -d "$lproj" ]] || continue
    ditto "$lproj" "$resources_dir/$(basename "$lproj")"
  done
  for strings_file in "$resources_dir"/*.lproj/*.strings; do
    [[ -s "$strings_file" ]] || continue
    plutil -lint "$strings_file" >/dev/null || die "Invalid strings file: $strings_file"
  done
}

sign_bundle() {
  local app_dir="$1"
  codesign --force --sign - --identifier "$BUNDLE_ID.cli" "$app_dir/Contents/MacOS/$CLI_PRODUCT"
  codesign --force --sign - "$app_dir"
  codesign --verify --deep --strict "$app_dir"
}

verify_embedded_cli() {
  local cli="$1/Contents/MacOS/$CLI_PRODUCT" reported
  reported="$("$cli" --version)" || die "The embedded $CLI_PRODUCT failed to run"
  [[ "$reported" == *"$APP_VERSION"* ]] ||
    die "The embedded $CLI_PRODUCT reports '$reported', expected version $APP_VERSION"
}

assemble_bundle() {
  local app_dir="$1" bin_path="$2"
  local contents_dir="$app_dir/Contents"
  local macos_dir="$contents_dir/MacOS"
  local resources_dir="$contents_dir/Resources"

  log "Assembling $app_dir"
  rm -rf "$app_dir"
  mkdir -p "$macos_dir" "$resources_dir"
  install -m 755 "$bin_path/$APP_EXECUTABLE" "$macos_dir/$APP_EXECUTABLE"
  install -m 755 "$bin_path/$CLI_PRODUCT" "$macos_dir/$CLI_PRODUCT"

  generate_icon "$resources_dir/$ICON_NAME.icns"
  write_info_plist "$contents_dir/Info.plist"
  copy_localizations "$resources_dir"
}

main() {
  parse_args "$@"
  require_macos
  require_developer_tools
  require_commands swift sips iconutil codesign plutil ditto install
  [[ -f "$ICON_SOURCE" ]] || die "Icon source not found: $ICON_SOURCE"

  OUTPUT_DIR="$(absolute_path "$OUTPUT_DIR")"
  WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.build-app.XXXXXX")"
  trap cleanup EXIT
  discover_localizations

  local app_dir="$OUTPUT_DIR/$APP_NAME.app" bin_path
  build_products
  bin_path="$(swift_build --show-bin-path | tail -n 1)"
  assemble_bundle "$app_dir" "$bin_path"

  log "Ad-hoc signing"
  sign_bundle "$app_dir"
  verify_embedded_cli "$app_dir"

  log "Built $app_dir"
}

main "$@"
