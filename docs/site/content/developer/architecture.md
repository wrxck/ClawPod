---
title: "Architecture"
description: "How LegacyPodClaw's components fit together"
weight: 1
---

LegacyPodClaw is composed of 6 components, all built with Theos for iOS 6 ARMv7.

## Components

| Component | Description |
|-----------|------------|
| **LegacyPodClaw.app** | Main application — chat UI, agent loop, tool execution, 10 AI providers |
| **LegacyPodClawTweak** | MobileSubstrate tweak — home button, Spotlight, lock screen, NC, app switcher hooks |
| **LegacyPodClawNC** | Notification Center widget (`BBWeeAppController`) |
| **LegacyPodClawPrefs** | Settings.app preference bundle |
| **LegacyPodClawDaemon** | Root daemon (`clawpodd`) — IPC via `CPDistributedMessagingCenter`, IOKit, syslog |
| **wolfSSL** | Vendored TLS 1.2 library (iOS 6 system SSL only supports TLS 1.0) |

## Metrics

| Metric | Value |
|--------|-------|
| Source files | 77 |
| Lines of code | ~19,700 |
| Package size | ~400KB |
| Target | ARMv7, iOS 6.0+ |

## Framework Layout

The `Frameworks/` directory contains the core subsystems:

| Framework | Purpose |
|-----------|---------|
| `WebSocket/` | RFC 6455 WebSocket client (CFStream-based) |
| `Memory/` | Memory pool, LRU cache, pressure monitoring |
| `Store/` | SQLite wrapper with statement caching |
| `Gateway/` | OpenClaw gateway protocol v3 client |
| `Chat/` | Session and message management |
| `Agent/` | Local agent runtime with tool orchestration |
| `Server/` | HTTP server + gateway server |
| `Channels/` | Telegram, Discord, IRC, Slack, webhook bridges |
| `Providers/` | Multi-provider AI model registry with failover |
| `Tools/` | Extended tool catalog, guardrails, skill registry, system MCP |
| `Media/` | Media pipeline (audio encoding for Music.app) |
| `Plugin/` | Plugin SDK |
| `System/` | TLS client (wolfSSL wrapper), system utilities |

## IPC Model

The tweak (`LegacyPodClawTweak`) runs in SpringBoard's process. The main app runs as a separate process. They communicate via:

- `CPDistributedMessagingCenter` for the daemon (`clawpodd`) which provides root-level access
- The daemon handles IOKit queries (battery, hardware), syslog monitoring, and sandbox-escaped file reads
