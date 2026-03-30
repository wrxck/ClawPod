---
title: "LegacyPodClawMCP"
description: "MCP development tools for iOS 6 jailbreak development"
weight: 5
---

LegacyPodClawMCP is a Python MCP server that provides AI-assisted development tools for working with LegacyPodClaw and iOS 6 devices.

## Setup

```bash
pip3 install mcp paramiko
python3 LegacyPodClawMCP/server.py
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAWPOD_DEVICE_IP` | `127.0.0.1` | Device SSH host |
| `CLAWPOD_SSH_PORT` | `2222` | SSH port (via iproxy) |
| `CLAWPOD_SSH_USER` | `root` | SSH user |
| `CLAWPOD_SSH_PASS` | `alpine` | SSH password |
| `THEOS` | `~/theos` | Theos installation path |
| `IOS6_HEADERS` | `~/iOS-6-Headers` | iOS 6 headers path |
| `CLAWPOD_PROJECT` | `~/openclaw-ios6` | Project directory |

## Claude Code Integration

Add to your Claude Code MCP settings:

```json
{
  "mcpServers": {
    "clawpod": {
      "command": "python3",
      "args": ["/path/to/LegacyPodClawMCP/server.py"]
    }
  }
}
```

## Available Tools

### Device Tools

| Tool | Description |
|------|------------|
| `device_info` | Device model, iOS version, UDID |
| `device_ssh` | Execute shell command |
| `device_scp_get` | Download file from device |
| `device_scp_put` | Upload file to device |
| `device_install_deb` | Install .deb + respring |
| `device_respring` | Restart SpringBoard |
| `device_logs` | Read syslog (with filter) |
| `device_crash_reports` | List recent crash reports |
| `device_read_crash` | Read specific crash report |
| `device_processes` | List running processes |
| `device_packages` | List installed dpkg packages |
| `device_filesystem` | List directory contents |
| `device_read_file` | Read a text file |
| `device_disk_usage` | Show disk space |
| `device_memory` | Show memory usage |

### Class Dump Tools

| Tool | Description |
|------|------------|
| `class_dump` | Download binary and class-dump it |
| `class_dump_list_headers` | List headers from a dump |
| `class_dump_read_header` | Read a specific dumped header |

### iOS 6 Header Tools

| Tool | Description |
|------|------------|
| `ios_headers_search` | Search private headers by keyword |
| `ios_headers_read` | Read a header file |
| `ios_headers_list_classes` | List classes in a framework |

### Theos Build Tools

| Tool | Description |
|------|------------|
| `theos_build` | Build project |
| `theos_package` | Package into .deb |
| `theos_install` | Build + package + install |

### Status

| Tool | Description |
|------|------------|
| `clawpod_status` | Check installation status |
