#!/bin/zsh
# Builds build/Session Launcher.app from the Swift package and signs it.
#
# Signing uses the first "Apple Development" identity in the keychain, so macOS keeps the
# iTerm Automation permission across rebuilds. Set SIGN_IDENTITY to override, or "-" for
# ad-hoc signing (macOS may then ask for the permission again after each rebuild).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product SessionLauncher

app="build/Session Launcher.app"
mkdir -p "$app/Contents/MacOS"
cp -f .build/release/SessionLauncher "$app/Contents/MacOS/SessionLauncher"
cp -f Resources/Info.plist "$app/Contents/Info.plist"

identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -nE 's/.*"(Apple Development[^"]*)".*/\1/p' | head -1)}"
identity="${identity:--}"
codesign --force --sign "$identity" "$app"

echo "Built $app (signed with: $identity)"
