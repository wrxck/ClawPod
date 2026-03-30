---
title: "Troubleshooting"
description: "Common issues and solutions"
weight: 7
---

## SSH Connection Issues

iOS 6 uses legacy SSH algorithms. If you see:

```
no matching host key type found
```

Add these flags to your SSH/SCP commands:

```bash
-o HostKeyAlgorithms=ssh-rsa -o KexAlgorithms=diffie-hellman-group14-sha1
```

## "No matching key exchange method found"

Same cause — add `-o KexAlgorithms=diffie-hellman-group14-sha1`.

## LegacyPodClaw Doesn't Appear on Home Hold

1. Make sure MobileSubstrate is installed
2. Check that the tweak is loaded: `grep LegacyPodClaw /var/log/syslog`
3. Try respringing: `killall SpringBoard`
4. On iPhone 4S: home hold may trigger Siri first if the hook didn't load. Reboot and try again.

## High Memory Usage

LegacyPodClaw has an 80MB memory budget. If you're hitting limits:

- Close background apps
- Reduce the conversation length (start a new session)
- Check memory diagnostics in **Settings > LegacyPodClaw > Diagnostics**

The memory pressure monitor has 4 levels and auto-sheds at >90% budget.

## API Errors

- **401 Unauthorized:** Check your API key in Settings
- **429 Rate Limited:** Wait a moment, or configure a secondary provider for failover
- **Timeout:** The default timeout is 120 seconds. On slow connections, the request may time out before the model responds. Try a faster model or provider.

## Tweak Loads Into Wrong Apps

Ensure the tweak filter is set to `com.apple.springboard` only. This was fixed in v0.3.0 — if you're on an older version, update.

## Music Downloads Fail

- Check the proxy is running: `curl http://YOUR_COMPUTER_IP:18790/health`
- Ensure the device and computer are on the same network
- Check the proxy URL in Settings matches exactly
