#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
cd "$project_dir"

version="$(awk '/^version:/ {print $2; exit}' pubspec.yaml | tr '+' '-')"
package_name="simple-kiosk-macos-$version"
archive="$project_dir/dist/$package_name.zip"
stage_root="$(mktemp -d)"
stage="$stage_root/$package_name"
trap 'rm -rf "$stage_root"' EXIT

flutter pub get
flutter build macos --release

mkdir -p "$stage" "$project_dir/dist"
cp -R build/macos/Build/Products/Release/simple_kiosk.app "$stage/"
cp release/guides/MACOS_INSTALL_GUIDE.md "$stage/INSTALL_GUIDE.md"
cp release/guides/MENU_CONFIGURATION_GUIDE.md "$stage/MENU_CONFIG_GUIDE.md"

(
  cd "$stage"
  shasum -a 256 simple_kiosk.app/Contents/MacOS/simple_kiosk > SHA256SUMS.txt
)

rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$stage" "$archive"
echo "Created: $archive"
