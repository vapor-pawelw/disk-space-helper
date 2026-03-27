# Disk Space Helper
A lightweight macOS menu bar utility that monitors disk space across your volumes and alerts you when free space runs low.  

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

<img width="74" height="28" alt="Screenshot 2026-03-27 at 10 20 34" src="https://github.com/user-attachments/assets/1dae3338-d429-4caa-99c4-72a877d57b51" /><br />
<img width="459" height="106" alt="Screenshot 2026-03-27 at 10 18 49" src="https://github.com/user-attachments/assets/bd0d60ab-9097-4ab2-8fc1-78dc20e0d9d5" /><br />  

- **Menu Bar Monitor** — Shows the lowest free (or used) percentage across all monitored volumes right in your menu bar
- **Multi-Volume Support** — Automatically discovers and monitors internal volumes; choose which partitions to track
- **Configurable Alerts** — Set custom free-space thresholds (e.g. 10 GB, 1 GB) and get native macOS notifications when crossed
- **Sound Notifications** — Optional audio alerts for low disk space warnings
- **Launch at Login** — Starts automatically with your Mac (configurable)
- **Minimal & Native** — Pure SwiftUI, no Electron, no web views — just a tiny menu bar app

## Installation

### Homebrew (recommended)

```bash
brew install vapor-pawelw/tap/disk-space-helper
```

### Manual Download

1. Download `DiskSpaceHelper.dmg` or `DiskSpaceHelper.zip` from the [latest release](https://github.com/vapor-pawelw/disk-space-helper/releases/latest)
2. Mount the DMG or extract the ZIP
3. Drag **DiskSpaceHelper.app** to your `/Applications` folder

### Bypassing Gatekeeper (unsigned app)

This app is **not notarized** (no paid Apple Developer account). macOS will block it on first launch. To open it:

**Option A — Right-click to open (easiest)**
1. Right-click (or Control-click) on `DiskSpaceHelper.app`
2. Select **Open** from the context menu
3. Click **Open** in the dialog that appears
4. You only need to do this once — subsequent launches work normally

**Option B — Remove quarantine via Terminal**
```bash
xattr -cr /Applications/DiskSpaceHelper.app
```

**Option C — System Settings**
1. Try to open the app normally (it will be blocked)
2. Go to **System Settings > Privacy & Security**
3. Scroll down — you'll see a message about DiskSpaceHelper being blocked
4. Click **Open Anyway**

## Building from Source

### Prerequisites

- macOS 14.0+
- Xcode 16+
- [Tuist](https://tuist.dev) (for project generation)

### Build

```bash
# Clone the repo
git clone https://github.com/vapor-pawelw/disk-space-helper.git
cd disk-space-helper

# Generate Xcode project
tuist generate

# Build release binary
xcodebuild -project DiskSpaceHelper.xcodeproj \
  -scheme DiskSpaceHelper \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO

# The app bundle is at:
# build/Build/Products/Release/DiskSpaceHelper.app
```

### Create Release Artifacts

```bash
# Build, create ZIP and DMG
./scripts/build-release.sh
# Artifacts are in release/
```

## Configuration

Access settings via the menu bar icon > **Settings** (or `Cmd+,`).

| Tab | Options |
|-----|---------|
| **Partitions** | Choose which volumes to monitor |
| **Alerts** | Add/remove free-space thresholds, toggle sound |
| **General** | Launch at login, show used % vs free % |

## How It Works

Disk Space Helper runs as a menu bar app (`LSUIElement`). Every 60 seconds it polls mounted volumes via `FileManager`, filters for internal drives, and updates the menu bar label. When free space drops below any configured threshold, it fires a native `UNUserNotification` (with optional sound) and tracks fired alerts to avoid duplicates.

## License

MIT License. See [LICENSE](LICENSE) for details.
