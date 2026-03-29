---
title: "Supported Devices"
description: "Full device compatibility matrix"
weight: 4
---

LegacyPodClaw supports **all iOS 6 devices**.

| Device | RAM | iOS Version | Notes |
|--------|-----|-------------|-------|
| iPod Touch 4th gen | 256MB | 6.0-6.1.6 | Requires headset mic for voice input |
| iPhone 3GS | 256MB | 6.0-6.1.6 | |
| iPhone 4 | 512MB | 6.0-6.1.3 | |
| iPhone 4S | 512MB | 6.0-6.1.3 | Home hold intercepts Siri activation path |
| iPad 2 | 512MB | 6.0-6.1.3 | Layout adapts to screen size |
| iPad 3rd gen | 1GB | 6.0-6.1.3 | Layout adapts to screen size |
| iPad mini 1st gen | 512MB | 6.0-6.1.3 | Layout adapts to screen size |

## RAM Considerations

- **256MB devices** (iPod Touch 4, iPhone 3GS): LegacyPodClaw uses an 80MB memory budget. Close background apps for best performance.
- **512MB+ devices** (iPhone 4/4S, iPads): Comfortable headroom. Multiple apps can run alongside LegacyPodClaw.

## iPhone 4S Notes

The iPhone 4S has Siri, which also activates on home-button hold. LegacyPodClaw hooks `SBAssistantController` to intercept this. If Siri appears instead of LegacyPodClaw after installation, reboot the device.

## iPad Notes

LegacyPodClaw's UI adapts to the larger screen. The `UIDeviceFamily` in the package includes iPad (added in v0.3.0).
