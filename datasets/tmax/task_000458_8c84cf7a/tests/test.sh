#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import socket
import string
import struct
import subprocess
from pathlib import Path

import pytest
import requests

MALICIOUS_URL = "http://malicious.corp.attacker.local/auth_bypass"
SSH_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObXy6kR3/58P9zB1A/N+Qz5e7J5h2W6X8Y9rVp+aE9q attacker@evil.local"


def test_deployment_log():
    """Verify the deployment.log file contains the correct extracted data."""
    log_path = "/home/user/deployment.log"
    assert os.path.exists(log_path), f"Log file not found at {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    assert len(lines) >= 2, "deployment.log must contain at least two lines"
    assert lines[0] == MALICIOUS_URL, f"Line 1 mismatch. Expected {MALICIOUS_URL}, got {lines[0]}"
    assert lines[1] == SSH_KEY, f"Line 2 mismatch. Expected {SSH_KEY}, got {lines[1]}"


def test_gateway_artifact():
    gateway = Path("/home/user/gateway.sh")
    assert gateway.is_file(), "/home/user/gateway.sh is missing or is not a regular file"
    subprocess.run(["bash", "-n", str(gateway)], check=True, timeout=3)
    text = gateway.read_text(errors="replace")
    assert "socat" in text or "nc" in text, "gateway.sh must implement the service using socat or nc"


def test_http_gateway_malicious_url():
    """Verify the HTTP gateway blocks the malicious URL."""
    url = f"http://127.0.0.1:8080/redirect?target={MALICIOUS_URL}"
    try:
        response = requests.get(url, timeout=2, allow_redirects=False)
        assert response.status_code == 403, f"Expected 403 Forbidden for malicious URL, got {response.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP Gateway connection failed: {e}")


def test_http_gateway_relative_url():
    """Verify the HTTP gateway redirects relative URLs."""
    url = "http://127.0.0.1:8080/redirect?target=/settings"
    try:
        response = requests.get(url, timeout=2, allow_redirects=False)
        assert response.status_code == 302, f"Expected 302 Found for relative URL, got {response.status_code}"
        assert response.headers.get("Location") == "/settings", f"Expected Location header '/settings', got {response.headers.get('Location')}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP Gateway connection failed: {e}")


def test_http_gateway_external_url():
    """Verify the HTTP gateway blocks other external URLs."""
    url = "http://127.0.0.1:8080/redirect?target=http://google.com"
    try:
        response = requests.get(url, timeout=2, allow_redirects=False)
        assert response.status_code == 403, f"Expected 403 Forbidden for external URL, got {response.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP Gateway connection failed: {e}")


def test_http_gateway_general_policy():
    """Exercise the redirect policy with unpredictable paths and hosts."""
    token = ''.join(random.SystemRandom().choice(string.ascii_lowercase + string.digits) for _ in range(20))
    relative_targets = [
        f"/audit-{token}",
        f"/teams/{token}/dashboard",
        f"/{token}/settings/profile",
    ]
    external_targets = [
        f"http://{token}.invalid/landing",
        f"https://outside-{token}.example.net/login",
        f"ftp://{token}.invalid/file",
    ]

    for target in relative_targets:
        response = requests.get(
            f"http://127.0.0.1:8080/redirect?target={target}",
            timeout=2,
            allow_redirects=False,
        )
        assert response.status_code == 302, f"Expected 302 for relative target {target!r}, got {response.status_code}"
        assert response.headers.get("Location") == target, f"Wrong Location for {target!r}"

    for target in external_targets:
        response = requests.get(
            f"http://127.0.0.1:8080/redirect?target={target}",
            timeout=2,
            allow_redirects=False,
        )
        assert response.status_code == 403, f"Expected 403 for external target {target!r}, got {response.status_code}"

    # A scheme-relative URL is external, despite beginning with a slash.
    response = requests.get(
        f"http://127.0.0.1:8080/redirect?target=//{token}.invalid/path",
        timeout=2,
        allow_redirects=False,
    )
    assert response.status_code == 403, "Scheme-relative external URLs must be forbidden"


def _listeners_on_port(port):
    listeners = []
    for table, family in (("/proc/net/tcp", socket.AF_INET), ("/proc/net/tcp6", socket.AF_INET6)):
        if not os.path.exists(table):
            continue
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                local_hex, port_hex = fields[1].rsplit(":", 1)
                if int(port_hex, 16) != port or fields[3] != "0A":
                    continue
                if family == socket.AF_INET:
                    address = socket.inet_ntoa(struct.pack("<I", int(local_hex, 16)))
                else:
                    raw = bytes.fromhex(local_hex)
                    address = socket.inet_ntop(socket.AF_INET6, b''.join(raw[i:i+4][::-1] for i in range(0, 16, 4)))
                listeners.append((family, address, fields[9]))
    return listeners


def _owners_of_socket_inode(inode):
    owners = []
    needle = f"socket:[{inode}]"
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    if os.readlink(fd) == needle:
                        owners.append(int(proc.name))
                        break
                except OSError:
                    pass
        except (OSError, PermissionError):
            pass
    return owners


def _sshd_test_arguments(cmdline):
    args = []
    i = 1
    while i < len(cmdline):
        arg = cmdline[i]
        if arg in ("-f", "-o", "-p") and i + 1 < len(cmdline):
            args.extend([arg, cmdline[i + 1]])
            i += 2
            continue
        if (arg.startswith("-f") or arg.startswith("-o") or arg.startswith("-p")) and len(arg) > 2:
            args.append(arg)
        i += 1
    return args


def _effective_sshd_config(pid):
    exe = os.readlink(f"/proc/{pid}/exe")
    raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    cmdline = [item.decode(errors="replace") for item in raw if item]
    command = [exe, "-T"] + _sshd_test_arguments(cmdline) + ["-C", "user=user,host=localhost,addr=127.0.0.1"]
    result = subprocess.run(command, text=True, capture_output=True, timeout=5)
    assert result.returncode == 0, f"Unable to inspect effective sshd configuration: {result.stderr}"
    config = {}
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        key, _, value = line.partition(" ")
        config.setdefault(key.lower(), []).append(value.strip())
    return config


def _one(config, key):
    values = config.get(key, [])
    assert values, f"Effective sshd configuration omitted {key}"
    return values[-1].lower()


def test_ssh_service_running():
    """Verify a real, non-root OpenSSH server is strictly bound to 127.0.0.1:2222."""
    listeners = _listeners_on_port(2222)
    assert listeners, "SSH service is not listening on 127.0.0.1:2222"
    assert len(listeners) == 1, f"Port 2222 must have exactly one listening socket, found {listeners}"
    family, address, inode = listeners[0]
    assert family == socket.AF_INET and address == "127.0.0.1", f"SSH must listen strictly on 127.0.0.1:2222, found {address}"

    owners = _owners_of_socket_inode(inode)
    assert owners, "Could not identify the process owning port 2222"
    user_uid = pwd.getpwnam("user").pw_uid
    for pid in owners:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        status = Path(f"/proc/{pid}/status").read_text()
        uid_line = next(line for line in status.splitlines() if line.startswith("Uid:"))
        effective_uid = int(uid_line.split()[2])
        assert exe == "sshd", f"Port 2222 is owned by {exe}, not sshd"
        assert effective_uid == user_uid and effective_uid != 0, "The listening sshd must run as the non-root user 'user'"

    config = _effective_sshd_config(owners[0])
    assert _one(config, "passwordauthentication") == "no"
    assert _one(config, "kbdinteractiveauthentication") == "no"
    assert _one(config, "hostbasedauthentication") == "no"
    assert _one(config, "pubkeyauthentication") == "yes"
    assert _one(config, "permitrootlogin") == "no"
    assert _one(config, "permitemptypasswords") == "no"
    assert _one(config, "kexalgorithms") == "curve25519-sha256@libssh.org"
    assert _one(config, "authorizedkeyscommand") == "none", "AuthorizedKeysCommand could authorize additional keys"
    assert _one(config, "trustedusercakeys") == "none", "A trusted CA could authorize additional keys"

    configured_files = config.get("authorizedkeysfile", [])
    assert configured_files, "No AuthorizedKeysFile is configured"
    key_lines = []
    home = pwd.getpwnam("user").pw_dir
    for value in configured_files:
        for configured_path in value.split():
            configured_path = configured_path.replace("%h", home).replace("%u", "user").replace("%%", "%")
            path = Path(configured_path if os.path.isabs(configured_path) else os.path.join(home, configured_path))
            if path.is_file():
                key_lines.extend(
                    line.strip() for line in path.read_text(errors="replace").splitlines()
                    if line.strip() and not line.lstrip().startswith("#")
                )
    assert key_lines == [SSH_KEY], f"The user must authorize only the extracted key; found {key_lines}"

    with socket.create_connection(("127.0.0.1", 2222), timeout=2) as sock:
        sock.settimeout(2)
        banner = sock.recv(512)
    assert banner.startswith(b"SSH-2.0-OpenSSH_"), f"Port 2222 did not present an OpenSSH protocol banner: {banner!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
