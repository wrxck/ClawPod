---
title: "Changelog"
description: "Release history"
weight: 5
---

## v0.3.0

- **Renamed** from ClawPod to LegacyPodClaw (naming conflict with existing project)
- **Expanded device support** to all iOS 6 devices (iPhone 3GS/4/4S, iPad 2/3/mini, iPod Touch 4)
- **Fixed tweak filter** — no longer loads into every app (was `com.apple.UIKit`, now `com.apple.springboard`). Fixes interference with Camera.app and other apps
- **Fixed uninstall** — resprings on removal so tweak hooks don't persist
- **Added iPhone 4S support** — hooks Siri activation (`SBAssistantController`)
- **Added iPad support** — `UIDeviceFamily` includes iPad, layout adapts to screen size
- **Updated package identifier** to `pro.matthesketh.legacypodclaw`

## v0.2.1

- Complete MediaLibrary integration
- Fixed sort order and audio format for Music.app

## v0.2.0

- Fixed MP3 encoding for iOS 6 playback
- Music download pipeline working end-to-end

## v0.1.0

- Initial release as ClawPod
- Full gateway + local agent
- Chat UI, streaming, sessions
- Tool system with guardrails
- 10 AI provider support
