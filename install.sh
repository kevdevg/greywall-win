#!/bin/sh
set -e

# Greywall Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/greyhavenhq/greywall/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/greyhavenhq/greywall/main/install.sh | sh -s -- v0.1.0

REPO="greyhavenhq/greywall"
BINARY="greywall"

OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
  Linux)  ;;
  Darwin) ;;
  *)      echo "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Version: first arg > env var > latest GitHub release
VERSION="${1:-${GREYWALL_VERSION:-}}"
if [ -z "$VERSION" ]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
fi
case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
VERSION_NUM="${VERSION#v}"

if [ -z "$VERSION_NUM" ]; then
  echo "Error: could not determine version"; exit 1
fi

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Archive name matches GoReleaser: greywall_0.1.0_Linux_x86_64.tar.gz
URL="https://github.com/$REPO/releases/download/${VERSION}/${BINARY}_${VERSION_NUM}_${OS}_${ARCH}.tar.gz"
CHECKSUM_URL="https://github.com/$REPO/releases/download/${VERSION}/checksums.txt"

# Show what we're about to do
echo ""
echo "Greywall Installer"
echo "-------------------"
echo ""
echo "Version:       $VERSION_NUM"
echo "Platform:      ${OS} ${ARCH}"
echo "Install to:    $INSTALL_DIR"
echo "Release notes: https://github.com/$REPO/releases/tag/$VERSION"

# Check for existing installation
UPGRADE=""
if [ -x "$INSTALL_DIR/$BINARY" ]; then
  CURRENT=$("$INSTALL_DIR/$BINARY" -v 2>/dev/null | awk '{print $2}' || echo "unknown")
  echo "Current:       $CURRENT"
  UPGRADE=1
fi

echo ""
if [ -n "$UPGRADE" ]; then
  echo "Ready to update the existing installation. This will:"
else
  echo "Ready to install greywall. This will:"
fi
echo "  1. Download greywall $VERSION from GitHub"
echo "  2. Verify the download checksum"
echo "  3. Install the binary to $INSTALL_DIR"
echo ""

printf "Proceed? [Y/n] "
read -r REPLY </dev/tty
case "$REPLY" in
  [nN]*) echo "Aborted."; exit 0 ;;
  *)     ;;
esac

echo ""

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading greywall $VERSION..."
curl -fsSL -o "$TMP/archive.tar.gz" "$URL"

# Verify checksum
if command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  SHA_CMD="shasum -a 256"
else
  SHA_CMD=""
fi

if [ -n "$SHA_CMD" ]; then
  curl -fsSL -o "$TMP/checksums.txt" "$CHECKSUM_URL"
  EXPECTED=$(grep "${BINARY}_${VERSION_NUM}_${OS}_${ARCH}.tar.gz" "$TMP/checksums.txt" | awk '{print $1}')
  ACTUAL=$($SHA_CMD "$TMP/archive.tar.gz" | awk '{print $1}')
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Error: checksum mismatch"; exit 1
  fi
  echo "Checksum verified."
fi

tar -xzf "$TMP/archive.tar.gz" -C "$TMP"

mkdir -p "$INSTALL_DIR"

mv "$TMP/$BINARY" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/$BINARY"

echo "Installed greywall $VERSION to $INSTALL_DIR"

# Always install/update greyproxy
echo ""
"$INSTALL_DIR/$BINARY" setup

# On macOS, install the system tray app
if [ "$OS" = "Darwin" ]; then
  echo ""
  echo "---"
  echo ""
  echo "Greywall includes a menu bar tray app for macOS."

  TRAY_URL="https://github.com/$REPO/releases/download/${VERSION}/greywall-tray_${VERSION_NUM}_Darwin_${ARCH}.tar.gz"
  APP_DIR="${HOME}/Applications"
  APP_BUNDLE="${APP_DIR}/Greywall.app"

  printf "Install Greywall menu bar app to %s? [Y/n] " "$APP_DIR"
  read -r TRAY_REPLY </dev/tty
  case "$TRAY_REPLY" in
    [nN]*) echo "Skipping tray app." ;;
    *)
      echo "Downloading greywall-tray $VERSION..."
      if curl -fsSL -o "$TMP/tray.tar.gz" "$TRAY_URL" 2>/dev/null; then
        if [ -n "$SHA_CMD" ]; then
          EXPECTED_TRAY=$(grep "greywall-tray_${VERSION_NUM}_Darwin_${ARCH}.tar.gz" "$TMP/checksums.txt" 2>/dev/null | awk '{print $1}' || true)
          if [ -n "$EXPECTED_TRAY" ]; then
            ACTUAL_TRAY=$($SHA_CMD "$TMP/tray.tar.gz" | awk '{print $1}')
            if [ "$EXPECTED_TRAY" != "$ACTUAL_TRAY" ]; then
              echo "Error: tray checksum mismatch"; exit 1
            fi
            echo "Tray checksum verified."
          fi
        fi

        tar -xzf "$TMP/tray.tar.gz" -C "$TMP"

        # Kill existing tray if running
        pkill -f 'Greywall.app/Contents/MacOS/greywall-tray' 2>/dev/null || true

        # Create .app bundle structure
        mkdir -p "$APP_BUNDLE/Contents/MacOS"
        mv "$TMP/greywall-tray" "$APP_BUNDLE/Contents/MacOS/greywall-tray"
        chmod +x "$APP_BUNDLE/Contents/MacOS/greywall-tray"

        # Create Info.plist
        cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>greywall-tray</string>
	<key>CFBundleName</key>
	<string>Greywall</string>
	<key>CFBundleIdentifier</key>
	<string>co.greyhaven.greywall-tray</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

        echo "Installed Greywall.app to $APP_DIR"

        # Offer to launch now
        printf "Launch Greywall menu bar app now? [Y/n] "
        read -r LAUNCH_REPLY </dev/tty
        case "$LAUNCH_REPLY" in
          [nN]*) ;;
          *)     open "$APP_BUNDLE" ;;
        esac

        # Offer to add as login item
        printf "Start Greywall automatically at login? [Y/n] "
        read -r LOGIN_REPLY </dev/tty
        case "$LOGIN_REPLY" in
          [nN]*) ;;
          *)
            osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP_BUNDLE\", hidden:true}" 2>/dev/null \
              && echo "Added Greywall to login items." \
              || echo "Note: Could not add login item automatically. You can add it manually in System Settings > General > Login Items."
            ;;
        esac
      else
        echo "Note: greywall-tray is not yet available for this release."
        echo "The menu bar app can be built from source: make build-tray"
      fi
      ;;
  esac
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo ""
    echo "$INSTALL_DIR is not in your PATH."
    echo "To use greywall right now, run:"
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    echo ""
    echo "To make it permanent, add that line to your shell profile:"
    SHELL_NAME=$(basename "${SHELL:-/bin/sh}")
    case "$SHELL_NAME" in
      zsh)  echo "  echo 'export PATH=\"\$PATH:$INSTALL_DIR\"' >> ~/.zshrc" ;;
      bash) echo "  echo 'export PATH=\"\$PATH:$INSTALL_DIR\"' >> ~/.bashrc" ;;
      fish) echo "  fish_add_path $INSTALL_DIR" ;;
      *)    echo "  echo 'export PATH=\"\$PATH:$INSTALL_DIR\"' >> ~/.\${SHELL}rc" ;;
    esac
    ;;
esac

echo ""
echo "----"
echo ""

"$INSTALL_DIR/$BINARY" check
