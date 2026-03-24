#!/usr/bin/env python3
"""
ClawPodMCP — Development Tools for iOS 6 Jailbreak
MCP server providing tools to interact with jailbroken iOS devices.

Tools:
  - device_info: Get connected device information
  - device_ssh: Execute command on device via SSH
  - device_scp_get: Download file from device
  - device_scp_put: Upload file to device
  - device_install_deb: Install .deb package on device
  - device_respring: Respring the device
  - device_logs: Read device syslog/crash reports
  - class_dump: Class-dump a binary from the device
  - theos_build: Build a Theos project
  - theos_package: Package a Theos project
  - theos_install: Build, package and install on device
  - ios_headers_search: Search iOS 6 headers for class/method
  - device_screenshot: Take a screenshot (if possible)
  - device_processes: List running processes
  - device_packages: List installed Cydia packages
  - device_filesystem: List directory contents on device
"""

import asyncio
import os
import re
import subprocess
import tempfile
from pathlib import Path

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("ClawPodMCP")

# Configuration
DEVICE_IP = os.environ.get("CLAWPOD_DEVICE_IP", "127.0.0.1")
DEVICE_PORT = int(os.environ.get("CLAWPOD_SSH_PORT", "2222"))
DEVICE_USER = os.environ.get("CLAWPOD_SSH_USER", "root")
DEVICE_PASS = os.environ.get("CLAWPOD_SSH_PASS", "alpine")
THEOS_PATH = os.environ.get("THEOS", os.path.expanduser("~/theos"))
IOS6_HEADERS = os.environ.get("IOS6_HEADERS", os.path.expanduser("~/iOS-6-Headers"))
PROJECT_DIR = os.environ.get("CLAWPOD_PROJECT", os.path.expanduser("~/openclaw-ios6"))

SSH_OPTS = (
    f"-o StrictHostKeyChecking=no "
    f"-o HostKeyAlgorithms=ssh-rsa "
    f"-o KexAlgorithms=diffie-hellman-group14-sha1 "
    f"-o ConnectTimeout=10"
)


def _ensure_iproxy():
    """Ensure iproxy is running for USB SSH tunnel."""
    result = subprocess.run(["pgrep", "-f", f"iproxy {DEVICE_PORT}"], capture_output=True)
    if result.returncode != 0:
        subprocess.Popen(
            ["iproxy", f"{DEVICE_PORT}:22"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        import time
        time.sleep(2)


def _ssh(command: str, timeout: int = 30) -> str:
    """Execute command on device via SSH."""
    _ensure_iproxy()
    cmd = (
        f"sshpass -p '{DEVICE_PASS}' ssh {SSH_OPTS} "
        f"-p {DEVICE_PORT} {DEVICE_USER}@{DEVICE_IP} '{command}'"
    )
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        output = result.stdout + result.stderr
        return output.strip()
    except subprocess.TimeoutExpired:
        return f"Command timed out after {timeout}s"
    except Exception as e:
        return f"SSH error: {e}"


def _scp_get(remote_path: str, local_path: str) -> str:
    """Download file from device."""
    _ensure_iproxy()
    cmd = (
        f"sshpass -p '{DEVICE_PASS}' scp {SSH_OPTS} "
        f"-P {DEVICE_PORT} {DEVICE_USER}@{DEVICE_IP}:{remote_path} {local_path}"
    )
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
    if result.returncode == 0:
        return f"Downloaded to {local_path}"
    return f"SCP error: {result.stderr}"


def _scp_put(local_path: str, remote_path: str) -> str:
    """Upload file to device."""
    _ensure_iproxy()
    cmd = (
        f"sshpass -p '{DEVICE_PASS}' scp {SSH_OPTS} "
        f"-P {DEVICE_PORT} {local_path} {DEVICE_USER}@{DEVICE_IP}:{remote_path}"
    )
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
    if result.returncode == 0:
        return f"Uploaded {local_path} to {remote_path}"
    return f"SCP error: {result.stderr}"


# === Device Tools ===

@mcp.tool()
def device_info() -> str:
    """Get connected iOS device information (model, iOS version, name, UDID)."""
    result = subprocess.run(["idevice_id", "-l"], capture_output=True, text=True)
    if not result.stdout.strip():
        return "No device connected via USB. Connect device and try again."

    udid = result.stdout.strip().split("\n")[0]
    info_parts = []
    for key in ["DeviceName", "ProductType", "ProductVersion", "BuildVersion",
                 "ModelNumber", "SerialNumber", "WiFiAddress"]:
        r = subprocess.run(["ideviceinfo", "-k", key], capture_output=True, text=True)
        if r.returncode == 0:
            info_parts.append(f"{key}: {r.stdout.strip()}")

    info_parts.insert(0, f"UDID: {udid}")
    return "\n".join(info_parts)


@mcp.tool()
def device_ssh(command: str, timeout: int = 30) -> str:
    """Execute a shell command on the device via SSH. Returns stdout+stderr."""
    return _ssh(command, timeout)


@mcp.tool()
def device_scp_get(remote_path: str, local_path: str = "") -> str:
    """Download a file from the device. If local_path is empty, downloads to /tmp/."""
    if not local_path:
        local_path = f"/tmp/{os.path.basename(remote_path)}"
    return _scp_get(remote_path, local_path)


@mcp.tool()
def device_scp_put(local_path: str, remote_path: str) -> str:
    """Upload a file to the device."""
    return _scp_put(local_path, remote_path)


@mcp.tool()
def device_install_deb(deb_path: str) -> str:
    """Install a .deb package on the device. Automatically resprings after."""
    if not os.path.exists(deb_path):
        return f"File not found: {deb_path}"
    result = _scp_put(deb_path, "/tmp/install.deb")
    if "error" in result.lower():
        return result
    return _ssh(
        "dpkg -i /tmp/install.deb && su mobile -c /usr/bin/uicache && killall SpringBoard",
        timeout=60,
    )


@mcp.tool()
def device_respring() -> str:
    """Respring the device (restart SpringBoard)."""
    return _ssh("killall SpringBoard")


@mcp.tool()
def device_logs(filter: str = "", lines: int = 50) -> str:
    """Read device syslog. Optionally filter by keyword."""
    if filter:
        return _ssh(f"grep -i '{filter}' /var/log/syslog 2>/dev/null | tail -{lines}")
    return _ssh(f"tail -{lines} /var/log/syslog 2>/dev/null")


@mcp.tool()
def device_crash_reports(count: int = 5) -> str:
    """List recent crash reports from the device."""
    return _ssh(
        f"ls -lt /var/mobile/Library/Logs/CrashReporter/*.plist 2>/dev/null | head -{count}"
    )


@mcp.tool()
def device_read_crash(filename: str) -> str:
    """Read a specific crash report. Use device_crash_reports to find filenames."""
    path = f"/var/mobile/Library/Logs/CrashReporter/{filename}"
    return _ssh(f"cat '{path}' 2>/dev/null | head -100")


@mcp.tool()
def device_processes() -> str:
    """List running processes on the device."""
    return _ssh("ps aux 2>/dev/null || ps -ef 2>/dev/null")


@mcp.tool()
def device_packages(filter: str = "") -> str:
    """List installed Cydia/dpkg packages. Optionally filter by name."""
    if filter:
        return _ssh(f"dpkg -l | grep -i '{filter}'")
    return _ssh("dpkg -l")


@mcp.tool()
def device_filesystem(path: str = "/", max_depth: int = 1) -> str:
    """List directory contents on the device."""
    return _ssh(f"ls -la '{path}' 2>/dev/null")


@mcp.tool()
def device_read_file(remote_path: str, max_lines: int = 200) -> str:
    """Read a text file from the device."""
    return _ssh(f"head -{max_lines} '{remote_path}' 2>/dev/null")


@mcp.tool()
def device_disk_usage() -> str:
    """Show disk usage on the device."""
    return _ssh("df -h")


@mcp.tool()
def device_memory() -> str:
    """Show memory usage on the device."""
    return _ssh(
        "echo '=== Memory ==='; "
        "sysctl hw.memsize 2>/dev/null; "
        "echo '=== Top processes ==='; "
        "top -l 1 -n 10 2>/dev/null || echo 'top not available'"
    )


# === Class Dump ===

@mcp.tool()
def class_dump(binary_path: str, output_dir: str = "") -> str:
    """
    Class-dump a binary from the device. Downloads the binary,
    runs class-dump locally, returns the headers.
    If output_dir is empty, outputs to /tmp/classdump_<name>/
    """
    name = os.path.basename(binary_path)
    local_binary = f"/tmp/{name}"

    # Download binary
    result = _scp_get(binary_path, local_binary)
    if "error" in result.lower():
        return f"Failed to download binary: {result}"

    if not output_dir:
        output_dir = f"/tmp/classdump_{name}"
    os.makedirs(output_dir, exist_ok=True)

    # Try class-dump
    for cmd_name in ["class-dump", "classdump", "class_dump"]:
        result = subprocess.run(
            [cmd_name, "-H", "-o", output_dir, local_binary],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            headers = os.listdir(output_dir)
            return f"Dumped {len(headers)} headers to {output_dir}\nFiles: {', '.join(sorted(headers)[:20])}"

    return (
        "class-dump not found locally. Install with: brew install class-dump\n"
        "Or use ios_headers_search to search pre-dumped iOS 6 headers."
    )


@mcp.tool()
def class_dump_list_headers(binary_name: str) -> str:
    """List headers from a previous class-dump. Use class_dump first."""
    output_dir = f"/tmp/classdump_{binary_name}"
    if not os.path.isdir(output_dir):
        return f"No class dump found at {output_dir}. Run class_dump first."
    headers = sorted(os.listdir(output_dir))
    return f"{len(headers)} headers:\n" + "\n".join(headers)


@mcp.tool()
def class_dump_read_header(binary_name: str, header_name: str) -> str:
    """Read a specific header from a class dump."""
    path = f"/tmp/classdump_{binary_name}/{header_name}"
    if not os.path.exists(path):
        return f"Header not found: {path}"
    with open(path) as f:
        return f.read()


# === iOS 6 Headers ===

@mcp.tool()
def ios_headers_search(query: str, path: str = "") -> str:
    """
    Search iOS 6 private headers for a class name, method, or keyword.
    Searches ~/iOS-6-Headers/ by default.
    """
    search_path = path or IOS6_HEADERS
    if not os.path.isdir(search_path):
        return f"iOS 6 headers not found at {search_path}. Clone: git clone https://github.com/pigigaldi/iOS-6-Headers.git"

    result = subprocess.run(
        ["grep", "-rn", "--include=*.h", query, search_path],
        capture_output=True, text=True, timeout=10,
    )
    lines = result.stdout.strip().split("\n")
    if len(lines) > 50:
        lines = lines[:50]
        lines.append(f"... ({len(result.stdout.split(chr(10)))} total matches)")
    return "\n".join(lines) if lines[0] else "No matches found"


@mcp.tool()
def ios_headers_read(header_name: str) -> str:
    """Read a specific iOS 6 header file (e.g., 'SBUIController.h')."""
    search_path = IOS6_HEADERS
    for root, dirs, files in os.walk(search_path):
        if header_name in files:
            with open(os.path.join(root, header_name)) as f:
                return f.read()
    return f"Header '{header_name}' not found in {search_path}"


@mcp.tool()
def ios_headers_list_classes(framework: str = "SpringBoard") -> str:
    """List all class headers in a framework (default: SpringBoard)."""
    framework_path = os.path.join(IOS6_HEADERS, framework)
    if not os.path.isdir(framework_path):
        return f"Framework not found: {framework_path}"
    headers = sorted(f for f in os.listdir(framework_path) if f.endswith(".h"))
    return f"{len(headers)} headers in {framework}:\n" + "\n".join(headers)


# === Theos Build ===

@mcp.tool()
def theos_build(project_dir: str = "") -> str:
    """Build a Theos project. Uses the ClawPod project dir by default."""
    project = project_dir or PROJECT_DIR
    if not os.path.isdir(project):
        return f"Project not found: {project}"

    env = os.environ.copy()
    env["THEOS"] = THEOS_PATH
    env["PATH"] = f"{THEOS_PATH}/bin:{env.get('PATH', '')}"

    result = subprocess.run(
        ["make", "-C", project, "clean"],
        capture_output=True, text=True, env=env, timeout=30,
    )
    result = subprocess.run(
        ["make", "-C", project],
        capture_output=True, text=True, env=env, timeout=120,
    )

    errors = [l for l in result.stderr.split("\n") if "error:" in l.lower()]
    if errors:
        return f"Build FAILED:\n" + "\n".join(errors[:10])

    return f"Build succeeded.\n{result.stdout[-500:]}" if result.returncode == 0 else f"Build failed:\n{result.stderr[-500:]}"


@mcp.tool()
def theos_package(project_dir: str = "", release: bool = True) -> str:
    """Package a Theos project into a .deb."""
    project = project_dir or PROJECT_DIR
    env = os.environ.copy()
    env["THEOS"] = THEOS_PATH
    env["PATH"] = f"{THEOS_PATH}/bin:{env.get('PATH', '')}"

    cmd = ["make", "-C", project, "package"]
    if release:
        cmd.append("FINALPACKAGE=1")

    result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=120)

    # Find the .deb
    pkg_dir = os.path.join(project, "packages")
    if os.path.isdir(pkg_dir):
        debs = sorted(Path(pkg_dir).glob("*.deb"), key=os.path.getmtime, reverse=True)
        if debs:
            return f"Package built: {debs[0]} ({debs[0].stat().st_size // 1024}KB)"

    return f"Packaging output:\n{result.stdout[-500:]}\n{result.stderr[-500:]}"


@mcp.tool()
def theos_install(project_dir: str = "") -> str:
    """Build, package, and install on the connected device."""
    project = project_dir or PROJECT_DIR

    # Build
    build_result = theos_build(project)
    if "FAILED" in build_result:
        return build_result

    # Package
    pkg_result = theos_package(project)
    if "Package built:" not in pkg_result:
        return f"Package failed: {pkg_result}"

    # Find .deb
    pkg_dir = os.path.join(project, "packages")
    debs = sorted(Path(pkg_dir).glob("*.deb"), key=os.path.getmtime, reverse=True)
    if not debs:
        return "No .deb found after packaging"

    # Install
    install_result = device_install_deb(str(debs[0]))
    return f"{pkg_result}\n{install_result}"


# === Utility ===

@mcp.tool()
def clawpod_status() -> str:
    """Check ClawPod installation status on the connected device."""
    return _ssh(
        "echo '=== Package ==='; "
        "dpkg -s ai.openclaw.ios6 2>/dev/null | head -10; "
        "echo '=== App ==='; "
        "ls -la /Applications/ClawPod.app/ 2>/dev/null; "
        "echo '=== Tweak ==='; "
        "ls -la /Library/MobileSubstrate/DynamicLibraries/ClawPodTweak* 2>/dev/null; "
        "echo '=== Daemon ==='; "
        "launchctl list 2>/dev/null | grep clawpod; "
        "echo '=== Prefs ==='; "
        "cat /var/mobile/Library/Preferences/ai.openclaw.ios6.plist 2>/dev/null | head -20"
    )


if __name__ == "__main__":
    mcp.run()
