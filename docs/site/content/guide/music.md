---
title: "Music Downloads"
description: "Search YouTube and download songs to the Music app"
weight: 6
---

LegacyPodClaw can search YouTube and download songs directly to the iOS Music app.

## How It Works

- **Search** works directly on-device via YouTube's InnerTube API — no proxy needed
- **Downloading** requires a lightweight proxy server on your network, because YouTube now requires JavaScript signature deciphering that can't run on iOS 6
- Downloaded tracks are encoded as MP3 for iOS 6 Music.app compatibility and added to the device's media library

## Setting Up the Proxy

On a computer on the same network as your device:

```bash
pip3 install yt-dlp
python3 LegacyPodClawMCP/music_proxy.py
```

The proxy runs on port 18790.

## Configuring the Device

Go to **Settings > LegacyPodClaw > Local Agent > Music Proxy URL** and enter:

```
http://YOUR_COMPUTER_IP:18790
```

## Usage

Just ask the AI:

- "Play Bohemian Rhapsody"
- "Download the latest song by [artist]"
- "Search YouTube for [song name]"

The AI searches, shows results, and downloads your selection to the Music app.
