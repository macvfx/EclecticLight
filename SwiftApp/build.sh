#!/bin/zsh
# Builds the Eclectic Light Updater Mac app from this Swift package and
# packages it into a runnable .app bundle (ad-hoc signed for local use).
set -e
cd "$(dirname "$0")"

swift build -c release

APP="EclecticLightUpdater.app"
VERSION="1.5.3"
BUILD="13"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/EclecticLightUpdater "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Eclectic Light Updater</string>
	<key>CFBundleDisplayName</key>
	<string>Eclectic Light Updater</string>
	<key>CFBundleIdentifier</key>
	<string>co.eclecticlightupdater.app</string>
	<key>CFBundleVersion</key>
	<string>${BUILD}</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleExecutable</key>
	<string>EclecticLightUpdater</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep -s - "$APP"

echo "Built: $PWD/$APP"
echo "Run it with: open \"$PWD/$APP\""
echo "Headless test: \"$APP/Contents/MacOS/EclecticLightUpdater\" --dump"
