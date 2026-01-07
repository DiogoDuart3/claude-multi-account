#!/bin/bash

# =============================================================================
# Claude Multi-Account Switcher - Release Preparation Script
# =============================================================================
# This script prepares a release by:
# 1. Finding the latest build in the build/ directory
# 2. Asking for release type (major/minor/patch)
# 3. Auto-calculating the next version
# 4. Creating a zip, signing it, and generating appcast.xml entry
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
# Use -d flag to only get directories, excluding any .zip files
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

# Get current version from the built app's Info.plist
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1")

echo -e "${GREEN}✓${NC} Current version in build: ${YELLOW}$CURRENT_VERSION${NC} (build ${YELLOW}$CURRENT_BUILD${NC})"

# Get the latest version from appcast.xml (if it exists)
if [ -f "$APPCAST_FILE" ]; then
    APPCAST_VERSION=$(grep -o 'sparkle:shortVersionString>[^<]*' "$APPCAST_FILE" | head -1 | sed 's/sparkle:shortVersionString>//')
    if [ -n "$APPCAST_VERSION" ]; then
        echo -e "${GREEN}✓${NC} Latest published version: ${YELLOW}$APPCAST_VERSION${NC}"
    fi
fi

echo ""

# Parse current version into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-1}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

# Ask for release type
echo -e "${CYAN}What type of release is this?${NC}"
echo ""
echo -e "  ${YELLOW}1)${NC} Major  ($(($MAJOR + 1)).0.0) - Breaking changes, major new features"
echo -e "  ${YELLOW}2)${NC} Minor  ($MAJOR.$(($MINOR + 1)).0) - New features, backwards compatible"
echo -e "  ${YELLOW}3)${NC} Patch  ($MAJOR.$MINOR.$(($PATCH + 1))) - Bug fixes, small improvements"
echo -e "  ${YELLOW}4)${NC} Same   ($CURRENT_VERSION) - Re-release current version"
echo -e "  ${YELLOW}5)${NC} Custom - Enter version manually"
echo ""
read -p "Enter choice [1-5]: " RELEASE_TYPE

case $RELEASE_TYPE in
    1)
        NEW_VERSION="$(($MAJOR + 1)).0.0"
        ;;
    2)
        NEW_VERSION="$MAJOR.$(($MINOR + 1)).0"
        ;;
    3)
        NEW_VERSION="$MAJOR.$MINOR.$(($PATCH + 1))"
        ;;
    4)
        NEW_VERSION="$CURRENT_VERSION"
        ;;
    5)
        read -p "Enter version (e.g., 2.1.0): " NEW_VERSION
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

# Calculate build number (increment from current)
NEW_BUILD=$((CURRENT_BUILD + 1))
if [ "$RELEASE_TYPE" = "4" ]; then
    NEW_BUILD=$CURRENT_BUILD
fi

echo ""
echo -e "${GREEN}✓${NC} New version: ${YELLOW}$NEW_VERSION${NC} (build ${YELLOW}$NEW_BUILD${NC})"

# Confirm
echo ""
read -p "Proceed with this version? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${BLUE}Creating release package...${NC}"

# Create zip file
ZIP_NAME="ClaudeAccountSwitcher-v$NEW_VERSION.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

# Remove old zip if exists
rm -f "$ZIP_PATH"

# Create the zip
(cd "$LATEST_BUILD_FOLDER" && zip -r "$ZIP_PATH" ClaudeAccountSwitcher.app -x "*.DS_Store")

echo -e "${GREEN}✓${NC} Created: ${CYAN}$ZIP_NAME${NC}"

# Get file size
FILE_SIZE=$(stat -f%z "$ZIP_PATH")
echo -e "${GREEN}✓${NC} File size: ${YELLOW}$FILE_SIZE bytes${NC}"

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
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$NEW_VERSION/ClaudeAccountSwitcher.zip"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Release Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Version:      ${YELLOW}$NEW_VERSION${NC}"
echo -e "  Build:        ${YELLOW}$NEW_BUILD${NC}"
echo -e "  File Size:    ${YELLOW}$FILE_SIZE bytes${NC} ($(echo "scale=2; $FILE_SIZE / 1048576" | bc) MB)"
echo -e "  Zip Location: ${CYAN}$ZIP_PATH${NC}"
echo -e "  Download URL: ${CYAN}$DOWNLOAD_URL${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Appcast Entry (copy this to appcast.xml)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

APPCAST_ENTRY=$(cat << 'HEREDOC_END'
        <item>
            <title>Version VERSION_PLACEHOLDER</title>
            <pubDate>DATE_PLACEHOLDER</pubDate>
            <sparkle:version>BUILD_PLACEHOLDER</sparkle:version>
            <sparkle:shortVersionString>VERSION_PLACEHOLDER</sparkle:shortVersionString>
            <description><![CDATA[
                <h2>What is New in VERSION_PLACEHOLDER</h2>
                <ul>
                    <li>TODO: Add your release notes here</li>
                </ul>
            ]]></description>
            <enclosure 
                url="URL_PLACEHOLDER"
                sparkle:version="BUILD_PLACEHOLDER"
                sparkle:shortVersionString="VERSION_PLACEHOLDER"
                sparkle:edSignature="SIGNATURE_PLACEHOLDER"
                length="SIZE_PLACEHOLDER"
                type="application/octet-stream" />
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
        </item>
HEREDOC_END
)

# Replace placeholders with actual values
APPCAST_ENTRY="${APPCAST_ENTRY//VERSION_PLACEHOLDER/$NEW_VERSION}"
APPCAST_ENTRY="${APPCAST_ENTRY//DATE_PLACEHOLDER/$PUB_DATE}"
APPCAST_ENTRY="${APPCAST_ENTRY//BUILD_PLACEHOLDER/$NEW_BUILD}"
APPCAST_ENTRY="${APPCAST_ENTRY//URL_PLACEHOLDER/$DOWNLOAD_URL}"
APPCAST_ENTRY="${APPCAST_ENTRY//SIGNATURE_PLACEHOLDER/$SIGNATURE}"
APPCAST_ENTRY="${APPCAST_ENTRY//SIZE_PLACEHOLDER/$FILE_SIZE}"

echo "$APPCAST_ENTRY"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Next Steps${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  1. ${YELLOW}Update appcast.xml${NC}"
echo -e "     Add the XML above as the first <item> inside <channel>"
echo ""
echo -e "  2. ${YELLOW}Create GitHub Release${NC}"
echo -e "     Tag: ${CYAN}v$NEW_VERSION${NC}"
echo -e "     Upload: ${CYAN}$ZIP_PATH${NC}"
echo -e "     (Rename to ClaudeAccountSwitcher.zip when uploading)"
echo ""
echo -e "  3. ${YELLOW}Update Info.plist${NC} (for next build)"
echo -e "     CFBundleShortVersionString: $NEW_VERSION"
echo -e "     CFBundleVersion: $NEW_BUILD"
echo ""
echo -e "  4. ${YELLOW}Commit and push${NC} appcast.xml to main branch"
echo ""
echo -e "${GREEN}Done! The zip is ready at: $ZIP_PATH${NC}"
