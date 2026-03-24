# ClawPod - Build & Install Guide

## Overview

Native Objective-C port of ClawPod AI assistant for jailbroken iOS 6 devices.
- **Target**: iPod Touch 4th gen (ARMv7, 256MB RAM, iOS 6.1.6)
- **Architecture**: PicoClaw-inspired lightweight native runtime
- **Memory budget**: 80MB app limit on 256MB device
- **No ARC**: Manual retain/release for maximum memory control

## Prerequisites

1. **Theos** - Install from https://theos.dev/docs/installation
   ```bash
   export THEOS=~/theos
   ```

2. **iOS 6.1 SDK** - Place in `$THEOS/sdks/iPhoneOS6.1.sdk`
   You can extract this from Xcode 4.6.3

3. **ldid** - For code signing (installed with Theos)

4. **dpkg** - For .deb packaging
   ```bash
   brew install dpkg  # macOS
   ```

## Build

```bash
cd openclaw-ios6
make clean
make package
```

This produces: `.theos/obj/debug/ClawPod.app` and a `.deb` package.

## Install

### Via SSH (device must be on same network)
```bash
make package install THEOS_DEVICE_IP=<ipod-ip-address>
```

### Via Cydia/Filza
1. Transfer the `.deb` file to the device
2. Install via `dpkg -i ai.openclaw.ios6_1.0.0_iphoneos-arm.deb`
3. Run `uicache` to refresh SpringBoard

## Configuration

### Gateway Connection
1. Open Settings tab
2. Enter your ClawPod gateway host/port
3. Enter auth token or password
4. Tap Connect

### Bonjour Discovery
The app auto-discovers ClawPod gateways broadcasting `_openclaw-gw._tcp` on the local network.

### Local Agent Mode
If no gateway is available, you can use the built-in agent:
1. Settings > Local Agent > API Key (enter your Anthropic API key)
2. The local agent runs directly on-device with minimal memory

## Architecture

```
openclaw-ios6/
├── Frameworks/           # Custom lightweight frameworks
│   ├── OCWebSocket/      # RFC 6455 WebSocket (CFStream-based)
│   ├── OCMemory/         # Memory pool, LRU cache, pressure monitor
│   ├── OCStore/          # SQLite wrapper with stmt caching
│   ├── OCGateway/        # ClawPod gateway protocol v3 client
│   ├── OCChat/           # Session & message management
│   └── OCAgent/          # PicoClaw-inspired local agent runtime
├── Classes/
│   ├── AppDelegate       # App lifecycle, service initialization
│   ├── UI/               # Full native UIKit GUI
│   │   ├── RootVC        # Tab controller (Chat/Sessions/Settings)
│   │   ├── ChatVC        # Streaming chat with message bubbles
│   │   ├── ChatCell      # Efficient message cell rendering
│   │   ├── SessionListVC # Session management
│   │   └── SettingsVC    # Connection, agent, memory diagnostics
│   ├── Services/
│   │   ├── Connection    # Bonjour gateway discovery
│   │   └── Voice         # AudioQueue mic input
│   └── Utils/
│       └── Logger        # Rotating file logger
├── Resources/
│   └── Info.plist
├── Makefile              # Theos build system
└── control               # Debian package metadata
```

## Memory Conservation

- Manual retain/release (no ARC overhead)
- 4KB read buffers for WebSocket (not 64KB)
- LRU cache with 2MB byte budget
- Message window: only 50 messages in RAM per session
- Older messages offloaded to SQLite
- Memory pressure monitor with 4 levels
- Auto-shed on terminal pressure (>90% budget)
- -Os optimization, dead code stripping

## Feature Parity with OpenClaw (openclaw.ai)

| Feature                  | Status |
|--------------------------|--------|
| Gateway WebSocket v3     | Full   |
| Chat with streaming      | Full   |
| Session management       | Full   |
| Auth (token/password)    | Full   |
| Bonjour discovery        | Full   |
| Local agent runtime      | Full   |
| MCP client support       | Full   |
| Built-in tools           | Full   |
| Voice input              | Full   |
| Memory management        | Full   |
| SQLite persistence       | Full   |
| Reconnection/backoff     | Full   |
| Dark theme UI            | Full   |
