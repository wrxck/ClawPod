# LegacyPodClawMCP

MCP (Model Context Protocol) development tools for LegacyPodClaw / iOS 6 jailbreak development.

## Tools

### Device
| Tool | Description |
|------|-------------|
| `device_info` | Get device model, iOS version, UDID |
| `device_ssh` | Execute shell command on device |
| `device_scp_get` | Download file from device |
| `device_scp_put` | Upload file to device |
| `device_install_deb` | Install .deb package + respring |
| `device_respring` | Restart SpringBoard |
| `device_logs` | Read syslog (with optional filter) |
| `device_crash_reports` | List recent crash reports |
| `device_read_crash` | Read a specific crash report |
| `device_processes` | List running processes |
| `device_packages` | List installed dpkg packages |
| `device_filesystem` | List directory contents |
| `device_read_file` | Read a text file |
| `device_disk_usage` | Show disk space |
| `device_memory` | Show memory usage |

### Class Dump
| Tool | Description |
|------|-------------|
| `class_dump` | Download binary from device and class-dump it |
| `class_dump_list_headers` | List headers from a previous dump |
| `class_dump_read_header` | Read a specific dumped header |

### iOS 6 Headers
| Tool | Description |
|------|-------------|
| `ios_headers_search` | Search iOS 6 private headers by keyword |
| `ios_headers_read` | Read a specific header file |
| `ios_headers_list_classes` | List all classes in a framework |

### Theos Build
| Tool | Description |
|------|-------------|
| `theos_build` | Build a Theos project |
| `theos_package` | Package into .deb |
| `theos_install` | Build + package + install on device |

### LegacyPodClaw
| Tool | Description |
|------|-------------|
| `clawpod_status` | Check LegacyPodClaw installation status |

## Setup

```bash
pip3 install mcp paramiko
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
| `CLAWPOD_PROJECT` | `~/openclaw-ios6` | LegacyPodClaw project directory |

## Usage with Claude Code

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

Then ask Claude to interact with your device:
- "What's the device info?"
- "Search iOS 6 headers for SBAwayLockBar"
- "Build and install LegacyPodClaw on the device"
- "Class-dump SpringBoard and find camera-related methods"
- "Read the crash log from the latest crash"
