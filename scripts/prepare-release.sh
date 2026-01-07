#!/bin/bash

# =============================================================================
# Claude Multi-Account Switcher - Release Preparation Script
# =============================================================================
# This script prepares a release by:
# 1. Finding the latest build in the build/ directory
# 2. Reading version from the built app
# 3. Creating a signed zip
# 4. Automatically updating appcast.xml
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
APPCAST_FILE="$PROJECT_ROOT/appcast.xml"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Claude Multi-Account Switcher - Release Preparation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Find the sign_update tool
SIGN_UPDATE_TOOL=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/artifacts/*" -type f 2>/dev/null | head -1)

if [ -z "$SIGN_UPDATE_TOOL" ]; then
    echo -e "${RED}Error: sign_update tool not found!${NC}"
    echo "Make sure you have built the project in Xcode with Sparkle package."
    exit 1
fi

# Find the latest build directory
if [ ! -d "$BUILD_DIR" ]; then
    echo -e "${RED}Error: Build directory not found: $BUILD_DIR${NC}"
    exit 1
fi

# Get the most recent build folder (sorted by name which includes timestamp)
LATEST_BUILD_FOLDER=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "ClaudeAccountSwitcher*" 2>/dev/null | sort -r | head -1)

if [ -z "$LATEST_BUILD_FOLDER" ]; then
    echo -e "${RED}Error: No builds found in $BUILD_DIR${NC}"
    echo "Please archive the app in Xcode first (Product → Archive → Distribute → Copy App)"
    exit 1
fi

APP_PATH="$LATEST_BUILD_FOLDER/ClaudeAccountSwitcher.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: App not found at $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found build: ${CYAN}$(basename "$LATEST_BUILD_FOLDER")${NC}"

# Get version from the BUILT app (not the source Info.plist)
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null)

if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
    echo -e "${RED}Error: Could not read version from built app${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Version in build: ${YELLOW}$VERSION${NC} (build ${YELLOW}$BUILD${NC})"

# Check if this version already exists in appcast
if grep -q "sparkle:shortVersionString>$VERSION<" "$APPCAST_FILE" 2>/dev/null; then
    echo -e "${YELLOW}⚠${NC}  Version $VERSION already exists in appcast.xml"
    read -p "Continue and overwrite? [y/N]: " OVERWRITE
    if [[ ! "$OVERWRITE" =~ ^[Yy] ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""
echo -e "${BLUE}Creating release package...${NC}"

# Create zip file
ZIP_NAME="ClaudeAccountSwitcher-v$VERSION.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

# Remove old zip if exists
rm -f "$ZIP_PATH"

# Create the zip
(cd "$LATEST_BUILD_FOLDER" && zip -rq "$ZIP_PATH" ClaudeAccountSwitcher.app -x "*.DS_Store")

echo -e "${GREEN}✓${NC} Created: ${CYAN}$ZIP_NAME${NC}"

# Get file size
FILE_SIZE=$(stat -f%z "$ZIP_PATH")
FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1048576" | bc)
echo -e "${GREEN}✓${NC} File size: ${YELLOW}$FILE_SIZE bytes${NC} ($FILE_SIZE_MB MB)"

# Sign the update
echo -e "${GREEN}✓${NC} Signing update..."
SIGN_OUTPUT=$("$SIGN_UPDATE_TOOL" "$ZIP_PATH")

# Extract just the signature
SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"$//')

if [ -z "$SIGNATURE" ]; then
    echo -e "${RED}Error: Could not extract signature${NC}"
    echo "Raw output: $SIGN_OUTPUT"
    exit 1
fi

echo -e "${GREEN}✓${NC} Signature generated"

# Generate current date in RFC 2822 format
PUB_DATE=$(date -R)

# GitHub repo info
GITHUB_REPO="DiogoDuart3/claude-multi-account"
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/ClaudeAccountSwitcher.zip"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Updating appcast.xml${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create a temp file for the new item
TEMP_ITEM=$(mktemp)
cat > "$TEMP_ITEM" << ITEMEOF
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <description><![CDATA[
                <h2>Version $VERSION</h2>
                <ul>
                    <li>Bug fixes and improvements</li>
                </ul>
            ]]></description>
            <enclosure 
                url="$DOWNLOAD_URL"
                sparkle:version="$BUILD"
                sparkle:shortVersionString="$VERSION"
                sparkle:edSignature="$SIGNATURE"
                length="$FILE_SIZE"
                type="application/octet-stream" />
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
        </item>

ITEMEOF

# Find the line number where we need to insert (after the --> comment)
INSERT_LINE=$(grep -n "^        -->" "$APPCAST_FILE" | head -1 | cut -d: -f1)

if [ -z "$INSERT_LINE" ]; then
    echo -e "${RED}Error: Could not find insertion point in appcast.xml${NC}"
    rm -f "$TEMP_ITEM"
    exit 1
fi

# Insert after that line
TEMP_FILE=$(mktemp)
head -n "$INSERT_LINE" "$APPCAST_FILE" > "$TEMP_FILE"
echo "" >> "$TEMP_FILE"
cat "$TEMP_ITEM" >> "$TEMP_FILE"
tail -n "+$((INSERT_LINE + 1))" "$APPCAST_FILE" >> "$TEMP_FILE"

# Replace the original file
mv "$TEMP_FILE" "$APPCAST_FILE"
rm -f "$TEMP_ITEM"

echo -e "${GREEN}✓${NC} Updated appcast.xml with version $VERSION"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Release Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Version:      ${YELLOW}$VERSION${NC}"
echo -e "  Build:        ${YELLOW}$BUILD${NC}"
echo -e "  File Size:    ${YELLOW}$FILE_SIZE_MB MB${NC}"
echo -e "  Zip Location: ${CYAN}$ZIP_PATH${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Next Steps${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${YELLOW}1. Create GitHub Release${NC}"
echo -e "     Go to: ${CYAN}https://github.com/$GITHUB_REPO/releases/new${NC}"
echo -e "     Tag:   ${CYAN}v$VERSION${NC}"
echo -e "     Upload: ${CYAN}$ZIP_PATH${NC}"
echo -e "     ${RED}Important: Rename to ClaudeAccountSwitcher.zip when uploading!${NC}"
echo ""
echo -e "  ${YELLOW}2. Commit and push appcast.xml${NC}"
echo -e "     git add appcast.xml"
echo -e "     git commit -m \"Release v$VERSION\""
echo -e "     git push"
echo ""
echo -e "${GREEN}Done! The release is ready.${NC}"
