#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--universal" ) ]]; then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
    printf 'AgentMeter requires macOS and Apple Command Line Tools.\n' >&2
    exit 1
fi

configuration="${CONFIGURATION:-release}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
    printf 'CONFIGURATION must be release or debug.\n' >&2
    exit 2
fi
mkdir -p "$project_dir/.build" "$project_dir/dist"
staging_dir="$(mktemp -d "$project_dir/.build/agentmeter-bundle.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
app_dir="$staging_dir/AgentMeter.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

if [[ "${1:-}" == "--universal" ]]; then
    binaries=()
    for architecture in arm64 x86_64; do
        target="$architecture-apple-macosx14.0"
        swift build --product AgentMeter -c "$configuration" --triple "$target"
        binary_dir="$(swift build -c "$configuration" --triple "$target" --show-bin-path)"
        binaries+=("$binary_dir/AgentMeter")
    done
    lipo -create "${binaries[@]}" -output "$app_dir/Contents/MacOS/AgentMeter"
    lipo "$app_dir/Contents/MacOS/AgentMeter" -verify_arch arm64 x86_64
else
    swift build --product AgentMeter -c "$configuration"
    binary_dir="$(swift build -c "$configuration" --show-bin-path)"
    cp "$binary_dir/AgentMeter" "$app_dir/Contents/MacOS/AgentMeter"
fi

cp Resources/Info.plist "$app_dir/Contents/Info.plist"
swift scripts/make-icon.swift "$staging_dir/AppIcon.iconset"
iconutil -c icns "$staging_dir/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
cp LICENSE "$app_dir/Contents/Resources/LICENSE.txt"
cp NOTICE.md "$app_dir/Contents/Resources/NOTICE.md"

# Ad-hoc signing is the default. A Developer ID identity may be supplied locally;
# notarization is a separate process and is not performed by this script.
codesign --force --sign "${CODESIGN_IDENTITY:--}" --options runtime "$app_dir"
codesign --verify --deep --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist"

# Only replace the generated bundle after the new bundle has passed verification.
rm -rf "$project_dir/dist/AgentMeter.app"
mv "$app_dir" "$project_dir/dist/AgentMeter.app"
printf '\nBuilt: %s\n' "$project_dir/dist/AgentMeter.app"
