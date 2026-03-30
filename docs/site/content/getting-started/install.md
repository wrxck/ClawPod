---
title: "Installation"
description: "How to install LegacyPodClaw on your jailbroken iOS 6 device"
weight: 1
---

## Requirements

- Jailbroken iOS 6.0-6.1.6 device
- [MobileSubstrate](http://cydia.saurik.com/package/mobilesubstrate/) (Cydia Substrate)
- [PreferenceLoader](http://cydia.saurik.com/package/preferenceloader/)

Grab the latest `.deb` from [GitHub Releases](https://github.com/wrxck/LegacyPodClaw/releases).

## SSH via USB (macOS / Linux)

This is the most reliable method. Requires [libimobiledevice](https://libimobiledevice.org/) for the USB tunnel.

```bash
brew install libimobiledevice sshpass
iproxy 2222:22 &

sshpass -p 'alpine' scp \
  -o HostKeyAlgorithms=ssh-rsa \
  -o KexAlgorithms=diffie-hellman-group14-sha1 \
  -P 2222 \
  pro.matthesketh.legacypodclaw_0.3.0_iphoneos-arm.deb \
  root@127.0.0.1:/tmp/legacypodclaw.deb

sshpass -p 'alpine' ssh \
  -o HostKeyAlgorithms=ssh-rsa \
  -o KexAlgorithms=diffie-hellman-group14-sha1 \
  -p 2222 root@127.0.0.1 \
  'dpkg -i /tmp/legacypodclaw.deb && su mobile -c /usr/bin/uicache && killall SpringBoard'
```

## SSH via WiFi

Find your device IP in **Settings > Wi-Fi > (i)**, then:

```bash
scp -o HostKeyAlgorithms=ssh-rsa \
  pro.matthesketh.legacypodclaw_0.3.0_iphoneos-arm.deb \
  root@DEVICE_IP:/tmp/legacypodclaw.deb

ssh -o HostKeyAlgorithms=ssh-rsa root@DEVICE_IP \
  'dpkg -i /tmp/legacypodclaw.deb && su mobile -c /usr/bin/uicache && killall SpringBoard'
```

Default SSH password: `alpine`

## SSH via USB (Windows)

1. Install [iTunes](https://www.apple.com/itunes/) (for USB drivers)
2. Run [iproxy](https://github.com/libimobiledevice-win32/imobiledevice-net): `iproxy 2222 22`
3. Connect with [WinSCP](https://winscp.net/) to `127.0.0.1:2222` (root / alpine)
4. Upload the `.deb` to `/tmp/legacypodclaw.deb`
5. In PuTTY: `dpkg -i /tmp/legacypodclaw.deb && su mobile -c /usr/bin/uicache && killall SpringBoard`

## iFile / Filza

Transfer the `.deb` to your device (via Safari download, AirDrop to a file manager, or email attachment). Open in iFile or Filza, tap **Install**, then respring.

## SSH Troubleshooting

iOS 6 uses legacy SSH algorithms. If you see `no matching host key type found`, add these flags to your SSH/SCP commands:

```bash
-o HostKeyAlgorithms=ssh-rsa -o KexAlgorithms=diffie-hellman-group14-sha1
```
