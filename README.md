# ClawPod

**AI Assistant for iOS 6** — a native Objective-C port of [OpenClaw](https://openclaw.ai) for jailbroken iOS devices.

> **v0.1.0** — experimental

## What is this?

ClawPod is a system-level AI assistant for jailbroken iOS 6 devices. It replaces core parts of iOS with AI-driven alternatives:

- **Hold the home button** → AI assistant overlay (replaces Voice Control)
- **Swipe left from home** → ClawPod dashboard (replaces Spotlight)
- **Notification Center** → Quick-ask AI widget
- **Lock screen** → Status display
- **Messages.app** → AI can message you directly
- **Shake any app** → Opens ClawPod
- **Optional: replace the entire home screen** with an agentic, conversation-driven launcher

Built from scratch in ~18,000 lines of Objective-C with **zero third-party dependencies**. Every framework is custom-written for the 256MB RAM constraints of the iPod Touch 4th generation.

## Install

### Download

Grab the `.deb` from [Releases](https://github.com/wrxck/ClawPod/releases).

### Prerequisites

- A jailbroken iOS 6.0–6.1.6 device (iPod Touch 4, iPhone 3GS/4/4S, iPad 2/3)
- **MobileSubstrate** (installed by default with most jailbreaks)
- **PreferenceLoader** (install from Cydia)

### Method 1: SSH via USB (macOS/Linux)

```bash
# Install tools (macOS)
brew install libimobiledevice sshpass

# USB SSH tunnel
iproxy 2222:22 &

# Copy and install
sshpass -p 'alpine' scp \
  -o HostKeyAlgorithms=ssh-rsa \
  -o KexAlgorithms=diffie-hellman-group14-sha1 \
  -P 2222 \
  ai.openclaw.ios6_0.1.0_iphoneos-arm.deb \
  root@127.0.0.1:/tmp/clawpod.deb

sshpass -p 'alpine' ssh \
  -o HostKeyAlgorithms=ssh-rsa \
  -o KexAlgorithms=diffie-hellman-group14-sha1 \
  -p 2222 root@127.0.0.1 \
  'dpkg -i /tmp/clawpod.deb && su mobile -c /usr/bin/uicache && killall SpringBoard'
```

### Method 2: SSH via USB (Windows)

1. Install [iTunes](https://www.apple.com/itunes/) (includes Apple USB drivers)
2. Download [iproxy](https://github.com/libimobiledevice-win32/imobiledevice-net) and run `iproxy 2222 22`
3. Use [WinSCP](https://winscp.net/) to connect to `127.0.0.1` port `2222` (user: `root`, password: `alpine`)
4. Upload the `.deb` to `/tmp/clawpod.deb`
5. Open terminal (PuTTY) to same address and run:
```
dpkg -i /tmp/clawpod.deb && su mobile -c /usr/bin/uicache && killall SpringBoard
```

### Method 3: SSH via WiFi (any OS)

Find your device IP in **Settings → Wi-Fi → (i) button**, then:

```bash
scp -o HostKeyAlgorithms=ssh-rsa ai.openclaw.ios6_0.1.0_iphoneos-arm.deb root@DEVICE_IP:/tmp/clawpod.deb
ssh -o HostKeyAlgorithms=ssh-rsa root@DEVICE_IP 'dpkg -i /tmp/clawpod.deb && su mobile -c /usr/bin/uicache && killall SpringBoard'
# Default password: alpine
```

### Method 4: iFile / Filza

1. Transfer the `.deb` to your device (email, Safari download, etc.)
2. Open in **iFile** or **Filza**
3. Tap **Install**
4. Respring

### SSH Legacy Algorithm Note

iOS 6 uses old SSH algorithms. If you see `no matching host key type found`, add:
```
-o HostKeyAlgorithms=ssh-rsa -o KexAlgorithms=diffie-hellman-group14-sha1
```

## Setup

1. **Settings → ClawPod** → Enter your API key (Anthropic, OpenAI, etc.)
2. **Hold home button** → ClawPod overlay appears
3. **Type a question** → Get streaming AI responses

### Optional: Agentic Launcher

Replace the stock home screen with an AI-driven launcher:

1. Settings → ClawPod → **Enable ClawPod Launcher** → ON
2. Respring
3. Toggle OFF and respring to restore stock SpringBoard

## Features

### System Integration

| Feature | Activation | What It Does |
|---------|-----------|-------------|
| AI Overlay | Hold home button | Siri-like streaming AI assistant |
| Dashboard | Swipe left from home | Quick actions + device status |
| NC Widget | Pull down NC | Quick-ask with inline responses |
| Lock Screen | Lock device | Status below clock |
| App Switcher | Double-tap home | Status widget page |
| Messages.app | AI-initiated | AI sends messages as "ClawPod" |
| Shake to Ask | Shake in any app | Opens AI overlay system-wide |
| Agentic Launcher | Toggle in settings | Replaces entire home screen |

### AI Providers (10)

Anthropic, OpenAI, Google/Gemini, Ollama, Groq, Together AI, OpenRouter, Mistral, Deepseek, Custom — with automatic failover.

### Tools

Shell execution, file CRUD, web search, notes & reminders, system MCP (brightness, volume, app launching, notifications, Messages.app integration), memory search, device diagnostics.

### Safety Guardrails

Blocks writes to system paths, dangerous commands, non-ClawPod SMS modifications. Rate-limited. Confirmation required for destructive operations.

### Gateway Server

Run the device as an OpenClaw-compatible gateway (HTTP + WebSocket on port 18789). Channels: Telegram, Discord, IRC, Slack, Webhooks.

### System Daemon

`clawpodd` — persistent root daemon with CPDistributedMessagingCenter IPC, IOKit hardware access, syslog monitoring, sandbox reading.

## Building from Source

```bash
# Requires macOS with Xcode, Theos, and iOS 14.5 SDK
export THEOS=~/theos
export PATH="$THEOS/bin:$PATH"

# Get SDKs
cd $THEOS/sdks
curl -sLO https://github.com/theos/sdks/archive/master.tar.gz
tar xzf master.tar.gz --strip-components=1 && rm master.tar.gz

# Build
cd /path/to/ClawPod
make clean && make package FINALPACKAGE=1
```

## Stats

| Metric | Value |
|--------|-------|
| Source files | 73 |
| Lines of code | 17,881 |
| Package size | 254KB |
| Architecture | ARMv7 iOS 6.0+ |
| Dependencies | Zero (all custom frameworks) |

## Credits

- **Author**: [Matt Hesketh](https://github.com/wrxck)
- **Based on**: [OpenClaw](https://openclaw.ai)
- **Inspired by**: [PicoClaw](https://github.com/sipeed/picoclaw), [NanoClaw](https://github.com/qwibitai/nanoclaw)
- **Built with**: [Theos](https://theos.dev)
- **Headers**: [iOS-6-Headers](https://github.com/pigigaldi/iOS-6-Headers)

## License

MIT
