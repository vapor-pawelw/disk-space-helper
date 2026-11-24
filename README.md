# Disk Space Helper
A lightweight macOS menu bar monitor that **keeps your disk from ever filling up.** It watches free space across your volumes, alerts you early, and **uses an AI agent (Claude Code or Codex) to find what to delete** — and, with Quick Recovery, to free space automatically before you hit 1%.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## 🛡️ Never Run Out of Disk Space

A full disk breaks builds, updates, Time Machine and sometimes the whole system. Disk Space Helper is a guard that stays in your menu bar and acts *before* that happens: alerts at your thresholds, AI-ranked cleanup suggestions when space gets low, and an automatic safety net at 1% free.

### 🤖 AI-Powered Disk Cleanup

**Works with both Claude Code and Codex.** Use whichever you already have, and switch any time.

**Stop guessing what is safe to delete.** When your disk fills up, Disk Space Helper asks the AI coding agent you already have installed, **Claude Code** or **Codex**, to rank what is worth removing, so you get a short, prioritized list instead of a hunt through Finder.

- **Ranked suggestions with real numbers** — Trash, old installers, Xcode archives, caches and more, each with its exact path, estimated size and the trade-off in plain language
- **See the result before you delete** — The review window shows how much your selection frees and the **free-space percentage you will have afterwards**
- **You stay in control** — Nothing is removed until you review the exact paths and confirm permanent deletion
- **Scan on demand** — Run **Scan for Cleanup Suggestions…** from the menu bar at any time, or let it start automatically when free space crosses your alert thresholds
- **Claude Code *and* Codex** — Pick either one and choose the model from a list. It uses the CLI you are already signed in to, so there is no extra account or API key

### ⚡ Quick Recovery: the 1% safety net

Opt in, and when a volume drops below **1% free** the agent picks safe, rebuildable cache files and **removes them automatically, with no prompt and no waiting for you**. Your disk does not get stuck at 0% while you are away from the keyboard.

- **Safe by design** — Only user cache files are considered, the agent can decline to delete anything, and every file is rechecked for changes and open handles right before removal
- **Stops as soon as it is enough** — Deletion ends once the volume is back to 1% free
- **Rate-limited** — Runs at most once every 30 minutes per volume, and takes priority over regular suggestions
- **Notifies you** — You get a notification and a menu bar summary of what was freed

Cleanup is opt-in. See [Optional Disk Cleanup](#optional-disk-cleanup) for what the agent sees and how it works.

## Features

<img width="74" height="28" alt="Screenshot 2026-03-27 at 10 20 34" src="https://github.com/user-attachments/assets/1dae3338-d429-4caa-99c4-72a877d57b51" /><br />
<img width="459" height="106" alt="Screenshot 2026-03-27 at 10 18 49" src="https://github.com/user-attachments/assets/bd0d60ab-9097-4ab2-8fc1-78dc20e0d9d5" /><br />  

- **Menu Bar Monitor** — Shows the lowest free (or used) percentage across all monitored volumes right in your menu bar
- **Multi-Volume Support** — Automatically discovers and monitors internal volumes; choose which partitions to track
- **Configurable Alerts** — Set custom free-space thresholds (e.g. 10 GB, 1 GB) and get native macOS notifications when crossed
- **Sound Notifications** — Optional audio alerts for low disk space warnings
- **Launch at Login** — Starts automatically with your Mac (configurable)
- **AI Disk Cleanup & Quick Recovery** — Optional Claude Code or Codex integration that ranks what to delete and automatically frees space below 1% (see above)
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
- Xcode 26+
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
| **Cleanup** | Opt in, select Claude Code or Codex, pick the model from a list, check CLI sign-in, and manage notifications |
| **General** | Launch at login, show used % vs free % |

## How It Works

Disk Space Helper runs as a menu bar app (`LSUIElement`). It polls mounted volumes every 60 seconds (15 seconds with Quick Recovery enabled) via `FileManager`, filters for internal drives, and updates the menu bar label. When free space reaches any configured threshold, it fires a native `UNUserNotification` (with optional sound) and tracks fired alerts to avoid duplicates.

### Optional Disk Cleanup

On first launch or the first update with cleanup onboarding, choose separately whether to enable Disk Cleanup and Quick Recovery. Existing choices carry over. You can change either setting under **Settings → Cleanup** after installing and signing in to Claude Code or Codex. Cleanup scans tracked volumes at a configured warning threshold or at 1% free. It aims to restore at least 5% free and asks you to review the exact paths before permanent deletion. You can also run a scan on demand from the menu bar with **Scan for Cleanup Suggestions…**, even when free space is above your thresholds. The **Review Disk Cleanup…** item appears only when there is something to review, and the review window shows how much each selection frees and the free-space percentage you would have afterwards.

The app inventories accessible file metadata locally and sends candidate names and allocated sizes to the selected provider for ranking. Claude Opus 5.5 and GPT-6.2 Sol are the defaults, both with medium reasoning. If macOS limits folder access, grant Disk Space Helper Full Disk Access to include those folders. For notifications that stay on screen, select **Persistent** (or **Alerts** on older versions) in macOS Notifications settings.

Enable **Quick Recovery** in the Cleanup tab to let the selected CLI choose cache files when free space drops below 1%. The agent sees file names, sizes, and access and modification ages from the user cache directory. It prioritizes safe, lasting gains and can return an empty selection. The app rechecks the selected files for changes and open handles, and stops deleting once the volume reaches 1% free. Quick Recovery takes priority over suggestions and can start once every 30 minutes per volume. It has its own opt-in and uses the configured CLI even if cleanup suggestions are off.

## License

MIT License. See [LICENSE](LICENSE) for details.
