---
title: "Memory Management"
description: "How LegacyPodClaw handles 256MB-1GB devices"
weight: 3
---

LegacyPodClaw runs on devices with 256MB to 1GB of RAM, with an 80MB app memory budget. Every byte matters.

## No ARC

The entire codebase uses manual retain/release (`-fno-objc-arc`). This eliminates ARC's overhead and gives complete control over object lifetimes.

## Memory Pool

The `MemoryPool` framework provides:

- Pre-allocated memory pools for frequently created objects
- Avoids repeated malloc/free cycles
- Pool sizes are tuned for each object type

## LRU Cache

A byte-budgeted LRU (Least Recently Used) cache:

- **2MB total budget** for cached data
- Automatically evicts oldest entries when budget is exceeded
- Used for API response caching, parsed data, etc.

## Message Windowing

Only **50 messages** are kept in RAM per chat session:

- Older messages are offloaded to SQLite via the `Store` framework
- Messages are loaded back on demand (scrolling up)
- SQLite uses statement caching to minimise allocation

## WebSocket Buffers

- **4KB read buffers** (not the typical 64KB)
- Chunked reading to avoid large allocations

## Memory Pressure Monitor

Four escalating levels:

| Level | Threshold | Action |
|-------|----------|--------|
| Normal | <50% budget | Normal operation |
| Warning | 50-70% budget | Flush non-essential caches |
| Critical | 70-90% budget | Reduce message window, flush all caches |
| Terminal | >90% budget | Auto-shed — aggressively release everything non-essential |

The monitor checks memory usage periodically and escalates/de-escalates as needed.
