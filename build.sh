#!/bin/bash
# Builds dist/Cuelight.app. Installs nothing: on first launch, the app installs
# the Claude Code hooks and the VS Code extension by itself (see README.md).
set -euo pipefail
cd "$(dirname "$0")"

app="dist/Cuelight.app"
version=$(plutil -extract version raw -o - vscode-extension/package.json)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

# VS Code extension, packaged as a .vsix (a zip with a manifest).
mkdir -p "$build/vsix/extension"
cp vscode-extension/package.json vscode-extension/extension.js "$build/vsix/extension/"
sips -z 128 128 assets/icon.png --out "$build/vsix/extension/icon.png" >/dev/null
cat > "$build/vsix/extension.vsixmanifest" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="cuelight" Version="$version" Publisher="louisbadr" />
    <DisplayName>Cuelight</DisplayName>
    <Description xml:space="preserve">Cuelight</Description>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.80.0" /></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code" /></Installation>
  <Dependencies />
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" /></Assets>
</PackageManifest>
EOF
cat > "$build/vsix/[Content_Types].xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json" />
  <Default Extension=".js" ContentType="application/javascript" />
  <Default Extension=".png" ContentType="image/png" />
  <Default Extension=".vsixmanifest" ContentType="text/xml" />
</Types>
EOF
(cd "$build/vsix" && zip -qrX ../cuelight.vsix .)

# App bundle: the Swift binary, the .vsix, and an Info.plist (LSUIElement = no Dock icon).
contents="$build/Cuelight.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
swiftc -O -o "$contents/MacOS/Cuelight" menubar-app/main.swift
cp "$build/cuelight.vsix" assets/Cuelight.icns "$contents/Resources/"
cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.louisbadr.cuelight</string>
  <key>CFBundleName</key><string>Cuelight</string>
  <key>CFBundleExecutable</key><string>Cuelight</string>
  <key>CFBundleIconFile</key><string>Cuelight</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$build/Cuelight.app" 2>/dev/null

rm -rf "$app"
mkdir -p dist
mv "$build/Cuelight.app" "$app"
echo "$app $version"
