# ClawPod

[![GitHub release](https://img.shields.io/github/v/release/wrxck/ClawPod?color=red)](https://github.com/wrxck/ClawPod/releases)
[![Platform](https://img.shields.io/badge/platform-iOS%206-blue)](https://github.com/wrxck/ClawPod)
[![Architecture](https://img.shields.io/badge/arch-ARMv7-orange)](https://github.com/wrxck/ClawPod)
[![Language](https://img.shields.io/badge/language-Objective--C-yellow)](https://github.com/wrxck/ClawPod)
[![License](https://img.shields.io/github/license/wrxck/ClawPod)](LICENSE)

**AI assistant for iOS 6** — a native Objective-C port of [OpenClaw](https://openclaw.ai) for jailbroken devices.

~19,000 lines of Objective-C. One vendored dependency ([wolfSSL](https://www.wolfssl.com/) for TLS 1.2). Everything else is hand-written for the 256MB RAM constraints of the iPod Touch 4th generation.

## Quick Start

1. Grab the `.deb` from [Releases](https://github.com/wrxck/ClawPod/releases)
2. Install via SSH, iFile, or Filza (see [Install](#install))
3. **Settings → ClawPod → Local Agent** → Enter your API key
4. **Hold the home button** → ClawPod appears

## How It Works

ClawPod hooks into iOS via MobileSubstrate to replace system surfaces with AI-powered alternatives:

| Gesture | What Happens |
|---------|-------------|
| Hold home button | AI overlay (replaces Voice Control) |
| Swipe left from home | Dashboard (replaces Spotlight) |
| Pull down Notification Center | Quick-ask widget |
| Lock device | Status display on lock screen |
| Double-tap home | Widget page in app switcher |
| Shake in any app | Opens AI overlay |

## Features

**AI Providers** — Anthropic, OpenAI, Google/Gemini, Ollama, Groq, Together AI, OpenRouter, Mistral, Deepseek, or any custom endpoint. Automatic failover between providers.

**Tool System** — Shell execution, file operations, web search, Notes & Reminders (direct database writes), Messages.app integration, system controls (brightness, volume, app launching), YouTube music search & download, device diagnostics, persistent memory.

**Gateway Server** — Run the device as an OpenClaw-compatible API server (HTTP + WebSocket on port 18789) with channel support for Telegram, Discord, IRC, Slack, and webhooks.

**System Daemon** — `clawpodd` provides root-level access via CPDistributedMessagingCenter IPC: battery/hardware info via IOKit, syslog monitoring, sandbox reading.

**Safety** — Protected system paths, blocked dangerous commands, rate limiting, confirmation prompts for destructive operations.

## Install

**Requirements:** Jailbroken iOS 6.0–6.1.6 (iPod Touch 4, iPhone 3GS/4/4S, iPad 2/3) with MobileSubstrate and PreferenceLoader.

<details>
<summary><b>SSH via USB (macOS/Linux)</b></summary>

```bash
brew install libimobiledevice sshpass
iproxy 2222:22 &

sshpass -p 'alpine' scp \
  -o HostKeyAlgorithms=ssh-rsa \
  -o KexAlgorithms=diffie-hellman-group14-sha1 \
  -P 2222 \
  ai.openclaw.ios6_0.2.0_iphoneos-arm.deb \
  root@127.0.0.1:/tmp/clawpod.deb

sshpass -p 'alpine' ssh \
  -o HostKeyAlgorithms=ssh-rsa \
  -o KexAlgorithms=diffie-hellman-group14-sha1 \
  -p 2222 root@127.0.0.1 \
  'dpkg -i /tmp/clawpod.deb && su mobile -c /usr/bin/uicache && killall SpringBoard'
```
</details>

<details>
<summary><b>SSH via WiFi</b></summary>

Find your device IP in **Settings → Wi-Fi → (i)**, then:

```bash
scp -o HostKeyAlgorithms=ssh-rsa \
  ai.openclaw.ios6_0.2.0_iphoneos-arm.deb \
  root@DEVICE_IP:/tmp/clawpod.deb

ssh -o HostKeyAlgorithms=ssh-rsa root@DEVICE_IP \
  'dpkg -i /tmp/clawpod.deb && su mobile -c /usr/bin/uicache && killall SpringBoard'
# Default password: alpine
```
</details>

<details>
<summary><b>SSH via USB (Windows)</b></summary>

1. Install [iTunes](https://www.apple.com/itunes/) (USB drivers)
2. Run [iproxy](https://github.com/libimobiledevice-win32/imobiledevice-net): `iproxy 2222 22`
3. Connect with [WinSCP](https://winscp.net/) → `127.0.0.1:2222` (root/alpine)
4. Upload `.deb` to `/tmp/clawpod.deb`
5. In PuTTY: `dpkg -i /tmp/clawpod.deb && su mobile -c /usr/bin/uicache && killall SpringBoard`
</details>

<details>
<summary><b>iFile / Filza</b></summary>

Transfer the `.deb` to your device → Open in iFile or Filza → Tap Install → Respring.
</details>

> **Note:** iOS 6 uses legacy SSH algorithms. If you see `no matching host key type found`, add `-o HostKeyAlgorithms=ssh-rsa -o KexAlgorithms=diffie-hellman-group14-sha1` to your SSH/SCP commands.

## Music Downloads

ClawPod can search YouTube and download songs to the Music app. Search works directly on device via YouTube's InnerTube API. Downloading requires a lightweight proxy server running on your network (YouTube now requires JavaScript signature deciphering that can't run on iOS 6).

```bash
pip3 install yt-dlp
python3 ClawPodMCP/music_proxy.py
```

Then set the proxy URL in **Settings → ClawPod → Local Agent → Music Proxy URL** to `http://YOUR_COMPUTER_IP:18790`.

## Building from Source

```bash
export THEOS=~/theos
export PATH="$THEOS/bin:$PATH"

# Get SDKs (if needed)
cd $THEOS/sdks
curl -sLO https://github.com/theos/sdks/archive/master.tar.gz
tar xzf master.tar.gz --strip-components=1 && rm master.tar.gz

# Build
cd /path/to/ClawPod
make clean && make package FINALPACKAGE=1
```

## ClawPodMCP

A Python MCP server for AI-assisted iOS 6 development — SSH/SCP, class-dumping, private header search, Theos build/install, crash analysis.

```bash
pip3 install mcp paramiko
python3 ClawPodMCP/server.py
```

See [ClawPodMCP/README.md](ClawPodMCP/README.md) for details.

## Architecture

| Component | Description |
|-----------|------------|
| **ClawPod.app** | Main application — chat UI, agent loop, tool execution, 10 AI providers |
| **ClawPodTweak** | MobileSubstrate tweak — home button, Spotlight, lock screen, NC, app switcher hooks |
| **ClawPodNC** | Notification Center widget (BBWeeAppController) |
| **ClawPodPrefs** | Settings.app preference bundle |
| **ClawPodDaemon** | Root daemon (`clawpodd`) — IPC, IOKit, syslog |
| **wolfSSL** | Vendored TLS 1.2 library (iOS 6 system SSL only supports TLS 1.0) |

| Metric | Value |
|--------|-------|
| Source files | 77 |
| Lines of code | ~19,700 |
| Package size | ~400KB |
| Target | ARMv7, iOS 6.0+ |

## Credits

- [Matt Hesketh](https://github.com/wrxck)
- Based on [OpenClaw](https://openclaw.ai)
- Inspired by [PicoClaw](https://github.com/sipeed/picoclaw) and [NanoClaw](https://github.com/qwibitai/nanoclaw)
- Built with [Theos](https://theos.dev)
- Headers from [iOS-6-Headers](https://github.com/pigigaldi/iOS-6-Headers)

## License

MIT
