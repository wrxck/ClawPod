---
title: "Tool System"
description: "What the AI can do on your device"
weight: 3
---

LegacyPodClaw's agent has a full tool system — it can interact with your device, the web, and other apps. Destructive operations require confirmation.

## Built-in Tools

| Tool | Description |
|------|------------|
| Date/Time | Current date, time, timezone |
| Device Info | Model, iOS version, storage, battery |
| Clipboard | Read/write system clipboard |
| HTTP Fetch | Fetch any URL |
| File Read | Read files from the filesystem |
| Math | Evaluate mathematical expressions |
| Timer | Set countdown timers |

## Extended Tools

### Shell & System

| Tool | Description |
|------|------------|
| Bash | Execute shell commands (with guardrails) |
| Process List | List running processes |
| Network Info | Network interfaces, IP addresses |
| Battery | Battery level and charging state |
| Storage | Disk space information |
| Notifications | Send local notifications |

### File Operations

| Tool | Description |
|------|------------|
| Write File | Write content to disk |
| Edit File | Search-and-replace editing |
| List Files | Directory listing |
| Delete File | Remove files (requires confirmation) |

### Web

| Tool | Description |
|------|------------|
| Web Search | Search via DuckDuckGo or Brave |
| Web Fetch | Download and read web pages |

### Image

| Tool | Description |
|------|------------|
| Describe Image | Send image to a vision model |
| Generate Image | Generate images via API |

### Memory

| Tool | Description |
|------|------------|
| Memory Store | Save information to persistent FTS memory |
| Memory Search | Full-text search across stored memories |

### Notes & Reminders

Direct database writes to the iOS Notes and Reminders apps — no URL scheme hacks, actual data modification.

### Messages

Integration with Messages.app for reading and composing.

### Multi-Agent

The agent can spawn sub-agents for complex tasks, delegating work while managing the overall conversation.

## Safety & Guardrails

- Protected system paths cannot be modified
- Dangerous commands are blocked (e.g. `rm -rf /`)
- Rate limiting prevents runaway tool execution
- Destructive operations show a confirmation prompt
- All tool invocations are logged
