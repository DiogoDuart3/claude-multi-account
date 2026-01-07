# Claude Multi-Account Switcher

A native macOS menu bar application designed to help power users manage multiple Claude (Anthropic) accounts and monitor usage limits in real-time.

<img src="menu-bar.png" width="400" alt="App Screenshot">

**Note:** This project is inspired by [CodexBar](https://github.com/joshua-wong/codexbar) and aims to provide similar robust usage tracking with multi-account switching capabilities.

## Features

*   **Multi-Account Support**: seamless switching between different Claude accounts.
*   **Real-time Usage Tracking**: Monitor both **Session** and **Weekly** rate limits directly from the menu bar.
*   **Smart Icon**: The menu bar icon dynamically updates to show session (top bar) and weekly (bottom bar) remaining capacity.
*   **Native & Lightweight**: Built with SwiftUI and AppKit for a native macOS experience.
*   **Secure**: Stores OAuth credentials securely in the macOS Keychain.
*   **Notifications**: Get notified when your rate limits reset or when you hit a limit.
*   **Auto-Fetching**: Automatically fetches the latest usage data using Claude's OAuth API.

## Installation

1.  Clone this repository.
2.  Open `ClaudeAccountSwitcher.xcodeproj` in Xcode.
3.  Ensure you have a valid signing team selected in the project settings.
4.  Build and Run (Cmd+R).
5.  Move the built application to your `/Applications` folder if desired.

## Building for Release (GitHub)

To create a shareable `.app` for GitHub Releases:

1.  Open the project in Xcode.
2.  Select **Product** > **Archive** from the menu bar.
3.  Once the archive finishes, the **Organizer** window will appear.
4.  Select the latest archive and click **Distribute App**.
5.  Choose **Custom** > **Copy App**.
6.  Save the `ClaudeAccountSwitcher.app` to your Desktop.
7.  Right-click the app and choose **Compress** to create a `.zip` file.
8.  Upload this zip file to your GitHub Release.

## Auto-Update System

This app uses [Sparkle](https://sparkle-project.org/) for automatic updates. Users will be notified when a new version is available.

https://github.com/user-attachments/assets/auto-update-showcase.mp4

<video src="auto-update-showcase.mp4" width="600" controls></video>

### Setting Up Sparkle (First Time Only)

1.  **Generate signing keys** (required for secure updates):
    ```bash
    # After adding Sparkle package in Xcode, find the generate_keys tool:
    # Usually at: ~/Library/Developer/Xcode/DerivedData/ClaudeAccountSwitcher-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
    
    # Run it to create your EdDSA key pair:
    ./generate_keys
    ```
    
2.  **Save the private key** securely (it will be added to your Keychain).
3.  **Add the public key** to your Xcode project:
    - Go to project settings → Build Settings
    - Search for "Other Swift Flags"
    - Or add to Info.plist as `SUPublicEDKey`

### Releasing a New Version

1.  **Update version numbers** in Xcode:
    - `CFBundleShortVersionString` (e.g., "1.1")
    - `CFBundleVersion` (increment build number, e.g., "2")

2.  **Archive and export** the app (see "Building for Release" above).

3.  **Sign the update**:
    ```bash
    # Find sign_update in the same Sparkle bin directory
    ./sign_update ClaudeAccountSwitcher.zip
    ```
    This outputs an EdDSA signature.

4.  **Create a GitHub Release**:
    - Tag: `v1.1` (matching your version)
    - Upload `ClaudeAccountSwitcher.zip`

5.  **Update `appcast.xml`**:
    ```xml
    <item>
        <title>Version 1.1</title>
        <pubDate>Tue, 07 Jan 2025 12:00:00 +0000</pubDate>
        <sparkle:version>2</sparkle:version>
        <sparkle:shortVersionString>1.1</sparkle:shortVersionString>
        <description><![CDATA[
            <h2>What's New</h2>
            <ul>
                <li>Your release notes here</li>
            </ul>
        ]]></description>
        <enclosure 
            url="https://github.com/DiogoDuart3/claude-multi-account/releases/download/v1.1/ClaudeAccountSwitcher.zip"
            sparkle:version="2"
            sparkle:shortVersionString="1.1"
            sparkle:edSignature="YOUR_SIGNATURE_FROM_STEP_3"
            length="FILE_SIZE_IN_BYTES"
            type="application/octet-stream" />
        <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
    </item>
    ```

6.  **Commit and push** the updated `appcast.xml` to the `main` branch.

Users will automatically be notified of the update!

## Usage

1.  **Adding an Account**:
    *   Click the menu bar icon.
    *   Select **Add Account...**.
    *   Enter a name for the account.
    *   A terminal window (or browser flow) will open to authenticate with Anthropic.
    *   Once logged in, the app will automatically detect the new credentials and fetch your usage data.

2.  **Switching Accounts**:
    *   Simply click on any account in the list to switch to it.
    *   The active account is highlighted with a blue indicator.

3.  **Removing Accounts**:
    *   Right-click on an inactive account in the list.
    *   Select **Remove** and confirm.

4.  **Checking for Updates**:
    *   Click the menu bar icon.
    *   Select **Check for Updates...**.
    *   The app also checks automatically on launch.

## Technical Details

*   **Authentication**: The app looks for credentials in `~/.claude/credentials.json` and the macOS Keychain (service: `Claude Code-credentials`).
*   **API**: Uses Anthropic's OAuth usage endpoint (`https://api.anthropic.com/api/oauth/usage`) to fetch precise rate limit data.
*   **Auto-Updates**: Uses Sparkle framework with EdDSA signatures for secure updates from GitHub.
*   **Compatibility**: Designed to work alongside the `claude` CLI tool.

## Requirements

*   macOS 13.0 (Ventura) or later.
*   Xcode 15+ for building.

## License

MIT License. See [LICENSE](LICENSE) file for details.

