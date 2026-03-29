---
title: "Gestures & Entry Points"
description: "All the ways to activate LegacyPodClaw"
weight: 1
---

LegacyPodClaw hooks into iOS via MobileSubstrate, replacing system surfaces with AI-powered alternatives. The tweak only loads into SpringBoard (`com.apple.springboard`), so it won't interfere with other apps.

## Home Button Hold

**Replaces:** Voice Control (most devices) / Siri (iPhone 4S)

Hold the home button to bring up the LegacyPodClaw AI overlay. This is the primary entry point.

On iPhone 4S, the tweak hooks `SBAssistantController` (Siri's activation path). On all other devices, it hooks the Voice Control activation.

## Swipe Left from Home Screen

**Replaces:** Spotlight Search

Swipe left from the first home screen page to open the LegacyPodClaw dashboard instead of Spotlight.

## Notification Center Widget

**Pull down from top of screen**

A quick-ask widget appears in Notification Center (implemented as a `BBWeeAppController`). Type a quick question without leaving your current app.

## Lock Screen Status

**Lock the device**

A status display on the lock screen shows recent AI activity or a configured status message.

## App Switcher Widget

**Double-tap home**

A widget page in the app switcher tray for quick access while multitasking.

## Shake Gesture

**Shake in any app**

Opens the AI overlay from anywhere. Useful when you don't want to leave your current app to hold the home button.
