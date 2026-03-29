# LegacyPodClaw Documentation Site — Design Spec

## Overview

Full documentation site for LegacyPodClaw at `legacypodclaw.hesketh.pro`. Covers both end-user guides (installation, configuration, usage) and developer documentation (architecture, building, plugin SDK, MCP tools). Static site built with Hugo, deployed via Fleet, DNS on Cloudflare.

## Audience

- **End users:** People installing LegacyPodClaw on jailbroken iOS 6 devices. Need clear install steps, provider setup, feature guides.
- **Developers/hackers:** People building from source, writing plugins, using the MCP server, or understanding the internals.

## Visual Design

Replicates the jailbreakme.com (3.0) aesthetic — iOS 4-era skeuomorphic style — with improvements to navigation and content readability for longer-form docs.

### Layout

- Centered container, max ~800px, 15px border-radius
- Linen-textured gray background (#c8cacc)
- Container has soft drop shadow for depth
- On desktop (>768px): sidebar nav + content area
- On mobile (<768px): single-column, jailbreakme-style with back-button nav

### Header

- 43px height, #7f94b0 background (iOS blue-gray)
- "LegacyPodClaw" centered in white, bold Helvetica Neue
- Back button on left: SVG arrow with section label, 44x44 hit target, hover state
- Improvement over jailbreakme: back button shows parent section name, not just arrow

### Navigation

- Landing page: iOS-style grouped table cells — #e1e1e1 rounded rows, disclosure arrows, 44px row height
- Section pages: sidebar nav on desktop for browsing without constant back-button use
- Page transitions: CSS transforms, 450ms slide (matching jailbreakme)

### Content Area

- White background inside container, 20px padding
- Body text: 15px Helvetica Neue
- Code blocks: #2d2d2d background, monospace, Terminal.app window style
- Tables: iOS grouped-cell aesthetic
- Callouts (tips, warnings): styled as iOS-style alert cells

### Footer

- #7f94b0 bar matching header
- Version number, GitHub link, "Built by Matt Hesketh", MIT license

### Typography

- Font stack: "Helvetica Neue", Helvetica, Arial, sans-serif
- Title: 24-30px bold
- Body: 15px regular
- Code: 13px monospace
- Text shadows: rgba(0,0,0,0.6) for depth on header elements

### Colors

| Element | Color |
|---------|-------|
| Background | #c8cacc |
| Container cells | #e1e1e1 |
| Header/footer bar | #7f94b0 |
| Active/link state | #0099FF |
| Content background | #ffffff |
| Code block background | #2d2d2d |
| Body text | #333333 |
| Header text | #ffffff |

## Site Structure

```
legacypodclaw.hesketh.pro/
├── /                        # Landing page (hero + feature overview)
├── /getting-started/
│   ├── install/             # All install methods (SSH USB/WiFi, iFile, Windows)
│   ├── configuration/       # Provider setup, gateway connection, Bonjour
│   └── first-run/           # What to expect, first interaction
├── /guide/
│   ├── gestures/            # Home hold, swipe left, NC, lock screen, shake, double-tap
│   ├── providers/           # Each AI provider: Anthropic, OpenAI, Google, Ollama, Groq, Together, OpenRouter, Mistral, Deepseek, custom
│   ├── tools/               # Shell, files, web search, Notes/Reminders, Messages, system controls, memory, diagnostics
│   ├── gateway/             # Running device as OpenClaw-compatible API server
│   ├── channels/            # Telegram, Discord, IRC, Slack, webhooks
│   ├── music/               # YouTube search, proxy setup, download to Music.app
│   └── troubleshooting/     # SSH issues, memory pressure, connectivity, common errors
├── /developer/
│   ├── architecture/        # Component diagram, how the 6 components fit together
│   ├── building/            # Theos setup, SDKs, build commands, packaging
│   ├── memory/              # Memory pool, LRU cache, pressure levels, 80MB budget
│   ├── plugin-sdk/          # Writing plugins with PluginSDK
│   ├── mcp-server/          # LegacyPodClawMCP tools, setup, Claude Code integration
│   └── internals/           # Agent runtime, provider registry, tool system, channel manager, guardrails
├── /devices/                # Full device compatibility matrix with notes
├── /changelog/              # Release history (v0.1.0 through v0.3.0+)
└── /about/                  # Credits, license, OpenClaw/PicoClaw/NanoClaw links
```

Approximately 20-25 pages total.

## Technical Implementation

### Stack

- **Generator:** Hugo (single Go binary, no Node deps)
- **Theme:** Custom `legacypodclaw` theme replicating jailbreakme.com aesthetic
- **JS:** Vanilla only — sidebar toggle, mobile nav, client-side search, optional page transitions
- **Search:** Hugo JSON index + lightweight client-side fuzzy search (~2KB)
- **Syntax highlighting:** Hugo's built-in Chroma

### Hugo Project Structure

```
docs/
├── hugo.toml                # Site config (baseURL, title, menus, params)
├── content/                 # Markdown pages following site structure above
│   ├── _index.md            # Landing page
│   ├── getting-started/
│   ├── guide/
│   ├── developer/
│   ├── devices.md
│   ├── changelog.md
│   └── about.md
├── themes/
│   └── legacypodclaw/
│       ├── layouts/
│       │   ├── _default/    # baseof.html, single.html, list.html
│       │   ├── partials/    # header.html, footer.html, sidebar.html, nav-cell.html
│       │   └── index.html   # Landing page template
│       ├── static/
│       │   ├── css/         # Main stylesheet
│       │   ├── js/          # sidebar.js, search.js
│       │   └── img/         # App icon, linen texture (CSS pattern), SVG back arrow
│       └── theme.toml
├── static/                  # Favicon, og-image
└── Makefile                 # build/deploy helpers
```

### Custom Shortcodes

- `{{< device-table >}}` — renders device compatibility matrix in iOS grouped-cell style
- `{{< callout type="tip|warning|note" >}}` — iOS-style alert cells
- `{{< gesture icon="home|swipe|shake" >}}` — gesture description cards

### Deployment

1. Hugo builds to `docs/public/`
2. Fleet serves `public/` as a static site
3. Cloudflare DNS: `legacypodclaw.hesketh.pro` → server
4. TLS via Cloudflare

### Content Authoring

All pages are Markdown with Hugo front matter:

```yaml
---
title: "Installing LegacyPodClaw"
description: "How to install on your jailbroken iOS 6 device"
weight: 1
---
```

Existing README.md and BUILD.md content will be restructured and expanded into the appropriate doc pages. No content is invented — everything derives from the actual codebase, header files, and existing documentation.
