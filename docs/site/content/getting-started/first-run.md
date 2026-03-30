---
title: "First Run"
description: "What to expect when you first launch LegacyPodClaw"
weight: 3
---

## Activating LegacyPodClaw

After installing and configuring a provider, LegacyPodClaw integrates into iOS through system gestures:

| Gesture | What Happens |
|---------|-------------|
| Hold home button | AI overlay appears (replaces Voice Control / Siri) |
| Swipe left from home | Dashboard (replaces Spotlight) |
| Pull down Notification Center | Quick-ask widget |
| Shake in any app | Opens AI overlay |

On iPhone 4S, the home-hold gesture hooks into the Siri activation path (`SBAssistantController`). On all other devices, it hooks Voice Control.

## Your First Conversation

1. **Hold the home button** — the LegacyPodClaw overlay appears
2. **Type or speak** — voice input uses the device microphone (iPod Touch 4 requires a headset mic)
3. **The AI responds** — streaming text appears in real-time
4. **Tools run automatically** — the AI can execute shell commands, search the web, manage files, and more (with confirmation prompts for destructive operations)

## Memory Constraints

LegacyPodClaw is designed for devices with 256MB-1GB RAM:

- The app has an 80MB memory budget
- Only 50 messages are kept in RAM per session; older messages are offloaded to SQLite
- Memory pressure is monitored at 4 levels, with auto-shedding above 90%
- Context is auto-compacted when token budgets are exceeded

You don't need to manage any of this — it happens automatically. But if the device feels slow, closing background apps helps.
