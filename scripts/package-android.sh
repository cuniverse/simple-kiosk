#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
cd "$project_dir"

version="$(awk '/^version:/ {print $2; exit}' pubspec.yaml | tr '+' '-')"
package_name="simple-kiosk-android-$version"
archive="$project_dir/dist/$package_name.zip"
stage_root="$(mktemp -d)"
stage="$stage_root/$package_name"
trap 'rm -rf "$stage_root"' EXIT

flutter pub get
flutter build apk --release

mkdir -p "$stage" "$project_dir/dist"
cp build/app/outputs/flutter-apk/app-release.apk "$stage/simple-kiosk.apk"
cp release/guides/ANDROID_INSTALL_GUIDE.md "$stage/INSTALL_GUIDE.md"
cp release/guides/MENU_CONFIGURATION_GUIDE.md "$stage/MENU_CONFIG_GUIDE.md"

(
  cd "$stage"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 simple-kiosk.apk > SHA256SUMS.txt
  else
    sha256sum simple-kiosk.apk > SHA256SUMS.txt
  fi
)

rm -f "$archive"
(
  cd "$stage_root"
  zip -q -r "$archive" "$package_name"
)
echo "Created: $archive"
