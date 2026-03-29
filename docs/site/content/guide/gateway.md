---
title: "Gateway Server"
description: "Run your iOS 6 device as an OpenClaw-compatible API server"
weight: 4
---

LegacyPodClaw can run as a gateway server, turning your device into an OpenClaw-compatible API endpoint accessible over the network.

## Overview

The gateway provides:

- **HTTP API** on port 18789
- **WebSocket** support for real-time streaming
- **Channel integrations** (Telegram, Discord, IRC, Slack, webhooks)
- **OpenClaw protocol v3** compatibility

## Enabling the Gateway

Go to **Settings > LegacyPodClaw > Gateway Server** and toggle it on. The server starts listening on `http://DEVICE_IP:18789`.

## HTTP API

The gateway exposes an OpenClaw-compatible chat API. Send requests to:

```
POST http://DEVICE_IP:18789/v1/chat
```

With a JSON body containing your message. The response streams back via chunked transfer encoding or WebSocket.

## WebSocket

Connect to `ws://DEVICE_IP:18789/ws` for real-time bidirectional communication. The WebSocket implementation is RFC 6455 compliant, built on CFStream (no third-party dependencies).

## Security

- Auth token or password required for all connections
- Configure in **Settings > LegacyPodClaw > Gateway Server > Auth**
