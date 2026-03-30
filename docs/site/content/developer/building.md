---
title: "Building from Source"
description: "Set up Theos and build LegacyPodClaw"
weight: 2
---

## Prerequisites

1. **Theos** — Install from [theos.dev](https://theos.dev/docs/installation)

```bash
export THEOS=~/theos
export PATH="$THEOS/bin:$PATH"
```

2. **iOS 6.1 SDK** — Place in `$THEOS/sdks/iPhoneOS6.1.sdk`. Extract from Xcode 4.6.3.

```bash
cd $THEOS/sdks
curl -sLO https://github.com/theos/sdks/archive/master.tar.gz
tar xzf master.tar.gz --strip-components=1 && rm master.tar.gz
```

3. **ldid** — For code signing (installed with Theos)

4. **dpkg** — For `.deb` packaging

```bash
brew install dpkg  # macOS
```

## Build

```bash
cd /path/to/LegacyPodClaw
make clean && make package FINALPACKAGE=1
```

This produces `.theos/obj/debug/LegacyPodClaw.app` and a `.deb` package in the `packages/` directory.

## Install on Device

```bash
make package install THEOS_DEVICE_IP=<device-ip>
```

Or manually via SCP + dpkg (see [Installation](/getting-started/install/)).

## Build Flags

The Makefile uses aggressive optimisation for the constrained hardware:

- `-fno-objc-arc` — manual retain/release for maximum memory control
- `-Os` — optimise for size
- `-ffast-math` — faster floating point
- `-fvisibility=hidden` — reduce binary size
- `-dead_strip` — remove unused code
- wolfSSL is linked as a static library (`libwolfssl.a`)

## Subprojects

The main Makefile builds all 4 subprojects:

- `LegacyPodClawPrefs` — Settings bundle
- `LegacyPodClawTweak` — MobileSubstrate tweak
- `LegacyPodClawNC` — Notification Center widget
- `LegacyPodClawDaemon` — Root daemon
