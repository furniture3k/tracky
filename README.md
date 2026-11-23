# Tracky

A tiny macOS menu bar time tracker. Click to start, click to stop. Tracky shows where your week went: weekly averages, trends, tags, and the hours you actually work.

- **Small:** under 1 MB to download. It uses about 12 MB of memory and 0% CPU while you're not tracking.
- **Tiny data:** about 6 bytes per session, so years of history fit in a few kilobytes.
- **Private:** no account, no network access, no analytics. Your data never leaves your Mac.

## Download

1. Download **Tracky.zip** from the [latest release](../../releases/latest).
2. Unzip it and drag **Tracky.app** into your **Applications** folder.
3. Open Tracky.

Tracky isn't notarized by Apple, so macOS will block it the first time you open it. To allow it:

- **macOS 15 or later:** open Tracky once. Then go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Tracky.
- **Older macOS:** right-click Tracky.app, choose **Open**, then click **Open** again.
- **Or, in Terminal:** `xattr -dr com.apple.quarantine /Applications/Tracky.app`

Requires macOS 14 Sonoma or later and runs natively on Apple Silicon and Intel Macs.

## Using it

| Action | How |
|---|---|
| Start / stop | **⌥⌘T** from anywhere, or right-click the menu bar icon |
| Open the panel | Click the menu bar icon |
| Tag your time | Pick a tag in the panel. Switching tags mid-session splits the session |
| Forgot to press start? | While tracking, the **−5m / −15m / −30m** buttons move the start time back |
| Started by accident? | **Discard** (you can undo it) |
| See your stats | **Stats** in the panel |

**Stats window**
- **Overview:**
  - This week compared with your usual pace by this point in the week.
  - Weekly average, time per work day, average session length and streak.
  - Weekly trend.
  - A day-by-day view you can page back through.
  - Time per tag, an average-by-weekday chart and an hour-by-day heatmap.
  - Insights such as your best day and busiest hour.
- **History:** filter, edit, add, duplicate or delete sessions.
- **Delete menu:** delete the last hour, today, or this week. You can undo straight after (⌘Z).
- **Export:** CSV for spreadsheets (⌘E).

**Settings** (gear icon in the panel)
- Auto-pause when idle, and resume when you're back. Idle time is never counted.
- What the menu bar shows: current session, today's total, or icon only.
- Weekly goal.
- Launch at login.

## Your data

Sessions are stored in `~/Library/Application Support/Tracky/data.trk`. It's a compact binary format: tags are written once, then each session is three variable-length integers (start offset, duration, tag and flags). Use **Export CSV** whenever you want a readable copy.

## Build from source

You only need the Xcode Command Line Tools (`xcode-select --install`), not full Xcode.

```sh
git clone <this repo> && cd Tracky
./scripts/build.sh --install    # build and copy to /Applications
swift test                      # run the tests
./scripts/build.sh --release    # universal build zipped to build/Tracky.zip
```

## License

MIT
