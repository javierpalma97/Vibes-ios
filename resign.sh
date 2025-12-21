#!/bin/bash

# Vibes - Resign Script for Free Apple Developer Accounts
# Free accounts require apps to be re-signed every 7 days
# This script automates the re-signing process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APP_NAME="Vibes"
BUNDLE_ID="com.vibes.app"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Vibes Re-sign Script           ║${NC}"
echo -e "${BLUE}║   Free Apple Developer Account       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}Error: Xcode is not installed or xcodebuild is not in PATH${NC}"
    exit 1
fi

# Check if xcrun is available
if ! command -v xcrun &> /dev/null; then
    echo -e "${RED}Error: xcrun command not found${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Fetching your development team...${NC}"
echo ""

# Get list of development teams
TEAMS=$(security find-identity -v -p codesigning | grep "iPhone Developer" | awk '{print $2}')

if [ -z "$TEAMS" ]; then
    echo -e "${RED}Error: No development certificates found${NC}"
    echo -e "${YELLOW}Please make sure you have:${NC}"
    echo "  1. Signed in to Xcode with your Apple ID"
    echo "  2. Created a development certificate"
    echo "  3. Go to Xcode > Preferences > Accounts > Manage Certificates"
    echo ""
    exit 1
fi

echo -e "${GREEN}Found development certificates:${NC}"
security find-identity -v -p codesigning | grep "iPhone Developer"
echo ""

# Get the first certificate
CERT_ID=$(echo "$TEAMS" | head -n 1)
CERT_NAME=$(security find-identity -v -p codesigning | grep "$CERT_ID" | sed 's/.*"\(.*\)"/\1/')

echo -e "${GREEN}Using certificate: ${NC}$CERT_NAME"
echo ""

# Get Team ID from certificate
TEAM_ID=$(security find-certificate -c "$CERT_NAME" -p | openssl x509 -noout -subject | sed -n 's/.*OU=\([^,]*\).*/\1/p')

if [ -z "$TEAM_ID" ]; then
    echo -e "${YELLOW}Could not automatically extract Team ID${NC}"
    echo -e "${YELLOW}Please enter your Team ID manually:${NC}"
    echo "(Find it in Xcode > Preferences > Accounts > Your Apple ID > Team ID)"
    read -p "Team ID: " TEAM_ID
fi

echo -e "${GREEN}Team ID: ${NC}$TEAM_ID"
echo ""

echo -e "${YELLOW}Step 2: Cleaning build folder...${NC}"
cd "$PROJECT_DIR/Vibes"

# Clean the build folder
xcodebuild clean -project Vibes.xcodeproj -scheme Vibes -configuration Debug >/dev/null 2>&1

echo -e "${GREEN}✓ Build folder cleaned${NC}"
echo ""

echo -e "${YELLOW}Step 3: Building and signing the app...${NC}"
echo -e "${BLUE}This may take a few minutes...${NC}"
echo ""

# Build and sign the app
xcodebuild \
    -project Vibes.xcodeproj \
    -scheme Vibes \
    -configuration Debug \
    -sdk iphoneos \
    -destination generic/platform=iOS \
    CODE_SIGN_IDENTITY="$CERT_NAME" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    PROVISIONING_PROFILE_SPECIFIER="" \
    build

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ App built and signed successfully!${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}✗ Build failed${NC}"
    echo -e "${YELLOW}Try these troubleshooting steps:${NC}"
    echo "  1. Open Xcode and build manually (Cmd+B)"
    echo "  2. Check that your certificate is valid"
    echo "  3. Make sure your device is registered in your developer account"
    echo ""
    exit 1
fi

echo -e "${YELLOW}Step 4: Finding connected devices...${NC}"
echo ""

# Get list of connected devices
DEVICES=$(xcrun xctrace list devices 2>&1 | grep -E "iPhone|iPad" | grep -v "Simulator" | head -n 5)

if [ -z "$DEVICES" ]; then
    echo -e "${YELLOW}No devices found${NC}"
    echo ""
    echo "Please connect your iPhone via USB and try again"
    echo ""
    exit 0
fi

echo -e "${GREEN}Connected devices:${NC}"
echo "$DEVICES" | nl
echo ""

# Auto-select first device
DEVICE_NAME=$(echo "$DEVICES" | head -n 1 | sed 's/ ([^)]*)$//')

echo -e "${GREEN}Using device: ${NC}$DEVICE_NAME"
echo ""

echo -e "${YELLOW}Step 5: Installing app on device...${NC}"
echo ""

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Vibes.app" -type d | grep "Debug-iphoneos" | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}Error: Could not find built app${NC}"
    echo "The app was built but the .app bundle was not found in DerivedData"
    exit 1
fi

echo -e "${BLUE}App location: ${NC}$APP_PATH"
echo ""

# Get device UDID
DEVICE_UDID=$(xcrun xctrace list devices 2>&1 | grep "$DEVICE_NAME" | sed -n 's/.*(\([^)]*\)).*/\1/p' | head -n 1)

if [ -z "$DEVICE_UDID" ]; then
    echo -e "${RED}Error: Could not get device UDID${NC}"
    exit 1
fi

# Install using xcrun devicectl (iOS 17+) or ios-deploy fallback
if command -v xcrun &> /dev/null && xcrun devicectl 2>&1 | grep -q "device install"; then
    echo -e "${BLUE}Using xcrun devicectl to install...${NC}"
    xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"
else
    # Fallback to simpler install method
    echo -e "${BLUE}Using cfgutil to install...${NC}"

    # Create IPA
    IPA_PATH="/tmp/${APP_NAME}.ipa"
    mkdir -p "/tmp/Payload"
    cp -r "$APP_PATH" "/tmp/Payload/"
    cd /tmp
    zip -qr "$IPA_PATH" Payload
    rm -rf Payload

    # Install IPA
    if command -v ideviceinstaller &> /dev/null; then
        ideviceinstaller -i "$IPA_PATH"
    else
        echo -e "${YELLOW}Note: Install libimobiledevice for automatic installation${NC}"
        echo -e "${YELLOW}brew install libimobiledevice${NC}"
        echo ""
        echo -e "${GREEN}App is ready at: ${NC}$APP_PATH"
        echo -e "${YELLOW}To install manually:${NC}"
        echo "  1. Open Xcode"
        echo "  2. Window > Devices and Simulators"
        echo "  3. Select your device"
        echo "  4. Drag $IPA_PATH to the Installed Apps section"
    fi

    rm -f "$IPA_PATH"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Re-sign Complete!            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Your app has been re-signed and is valid for 7 days${NC}"
echo -e "${YELLOW}Run this script again in 7 days to renew${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Launch Vibes on your iPhone"
echo "  2. If prompted, trust the developer certificate:"
echo "     Settings > General > VPN & Device Management"
echo "  3. Tap your certificate and select 'Trust'"
echo ""
echo -e "${BLUE}Enjoy the vibes! 🎵${NC}"
echo ""
