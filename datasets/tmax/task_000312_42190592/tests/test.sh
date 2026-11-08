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
import re
import stat
import socket
import subprocess
import time

import pytest
import requests

# The audio says "delta seven seven"; words are concatenated in uppercase.
PASSCODE = "DELTASEVENSEVEN"
LOG_FILE = "/home/user/app_logs/auth.log"


def test_provision_script_idempotent():
    path = "/home/user/provision.py"
    assert os.path.isfile(path), f"Provisioning script missing at {path}"

    # Run the script again to verify idempotency.
    result = subprocess.run(["python3", path], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Provisioning script failed on second run: {result.stderr}"


def test_directory_and_file_permissions():
    log_dir = "/home/user/app_logs/"
    log_file = LOG_FILE

    assert os.path.isdir(log_dir), f"Log directory missing at {log_dir}"
    dir_stat = os.stat(log_dir)
    assert stat.S_IMODE(dir_stat.st_mode) == 0o700, f"Log directory permissions incorrect: {oct(dir_stat.st_mode)}"

    assert os.path.isfile(log_file), f"Log file missing at {log_file}"
    file_stat = os.stat(log_file)
    assert stat.S_IMODE(file_stat.st_mode) == 0o600, f"Log file permissions incorrect: {oct(file_stat.st_mode)}"


def test_ssh_key_authorization():
    ssh_dir = "/home/user/.ssh"
    authorized = os.path.join(ssh_dir, "authorized_keys")
    assert os.path.isfile(authorized), "authorized_keys is missing"

    with open(authorized, encoding="utf-8") as f:
        authorized_blobs = {
            parts[1]
            for line in f
            if line.strip() and not line.lstrip().startswith("#")
            for parts in [line.split()]
            if len(parts) >= 2
        }
    assert authorized_blobs, "authorized_keys contains no SSH public key"

    derived_blobs = set()
    for name in os.listdir(ssh_dir):
        path = os.path.join(ssh_dir, name)
        if name.endswith(".pub") or name in {"authorized_keys", "config", "known_hosts"} or not os.path.isfile(path):
            continue
        result = subprocess.run(["ssh-keygen", "-y", "-f", path], capture_output=True, text=True)
        if result.returncode == 0:
            parts = result.stdout.split()
            if len(parts) >= 2:
                derived_blobs.add(parts[1])
    assert derived_blobs & authorized_blobs, "No generated private key matches authorized_keys"

    # Verify the user's default SSH setup actually permits noninteractive localhost login.
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "localhost", "printf", "SSH_OK"],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0 and result.stdout == "SSH_OK", (
        f"ssh localhost is not configured for passwordless noninteractive use: {result.stderr}"
    )


def test_logrotate_config():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"logrotate.conf missing at {conf_path}"

    # Run logrotate with the config to ensure it is valid.
    result = subprocess.run(["logrotate", "-d", conf_path], capture_output=True, text=True)
    assert result.returncode == 0, f"logrotate configuration is invalid: {result.stderr}"

    with open(conf_path, encoding="utf-8") as f:
        config = re.sub(r"(?m)#.*$", "", f.read())
    block_match = re.search(
        r'(?ms)^\s*["\']?/home/user/app_logs/auth\.log["\']?\s*\{(.*?)^\s*\}',
        config,
    )
    assert block_match, "No logrotate block for auth.log"
    block = block_match.group(1)
    assert re.search(r"(?m)^\s*daily\s*$", block), "auth.log is not configured for daily rotation"
    assert re.search(r"(?m)^\s*rotate\s+5\s*$", block), "auth.log does not keep exactly 5 backups"
    assert re.search(r"(?m)^\s*compress\s*$", block), "auth.log backups are not compressed"
    assert re.search(r"(?m)^\s*create\s+0?600(?:\s+\S+\s+\S+)?\s*$", block), "rotated auth.log is not recreated with mode 0600"


def test_http_over_ssh_tunnel():
    assert os.path.isfile("/home/user/auth_server.py"), "Authentication service script is missing"

    headers = {"X-Auth-Passcode": PASSCODE}
    try:
        response = requests.get("http://127.0.0.1:9999/", headers=headers, timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
        assert response.text.strip() == "ACCESS_GRANTED", f"Expected 'ACCESS_GRANTED', got '{response.text}'"
        assert response.text == "ACCESS_GRANTED", "HTTP success body is not exact"
    except requests.RequestException as e:
        pytest.fail(f"HTTP request over SSH tunnel failed: {e}")

    try:
        response = requests.get("http://127.0.0.1:9999/", timeout=5)
        assert response.status_code == 403, f"Expected HTTP 403, got {response.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"HTTP request over SSH tunnel failed: {e}")


def test_port_9999_is_an_ssh_tunnel():
    listener_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address, state, inode = fields[1], fields[3], fields[9]
                port = int(local_address.rsplit(":", 1)[1], 16)
                if port == 9999 and state == "0A":
                    listener_inodes.add(inode)
    assert listener_inodes, "Nothing is listening on local port 9999"

    matching_ssh = []
    for pid in (p for p in os.listdir("/proc") if p.isdigit()):
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
            if exe != "ssh":
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
            command = " ".join(argv)
            if not re.search(r"(?:^|\s)-L\s*(?:127\.0\.0\.1:)?9999:127\.0\.0\.1:8888(?:\s|$)", command):
                continue
            owned = set()
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    target = os.readlink(f"/proc/{pid}/fd/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match:
                    owned.add(match.group(1))
            if owned & listener_inodes:
                matching_ssh.append((pid, command))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    assert matching_ssh, "Port 9999 is not owned by an ssh process forwarding to 127.0.0.1:8888"

    # Also verify the specified backend is independently live.
    direct = requests.get(
        "http://127.0.0.1:8888/",
        headers={"X-Auth-Passcode": PASSCODE},
        timeout=5,
    )
    assert direct.status_code == 200
    assert direct.text == "ACCESS_GRANTED"


def test_raw_tcp_component():
    try:
        with socket.create_connection(("127.0.0.1", 8889), timeout=5) as s:
            s.sendall(f"{PASSCODE}\n".encode("utf-8"))
            response = s.recv(1024).decode("utf-8")
            assert response.strip() == "ACCESS_GRANTED", f"Expected 'ACCESS_GRANTED', got '{response}'"
            assert response == "ACCESS_GRANTED\n", f"TCP success response is not exact: {response!r}"
            assert s.recv(1) == b"", "TCP server did not close after one response"
    except (socket.error, socket.timeout) as e:
        pytest.fail(f"TCP connection failed: {e}")

    try:
        with socket.create_connection(("127.0.0.1", 8889), timeout=5) as s:
            s.sendall(b"WRONGPASS\n")
            response = s.recv(1024).decode("utf-8")
            assert response.strip() == "DENIED", f"Expected 'DENIED', got '{response}'"
            assert response == "DENIED\n", f"TCP denial response is not exact: {response!r}"
            assert s.recv(1) == b"", "TCP server did not close after one response"
    except (socket.error, socket.timeout) as e:
        pytest.fail(f"TCP connection failed: {e}")


def test_logging_behavior():
    assert os.path.isfile(LOG_FILE), f"Log file missing at {LOG_FILE}"
    with open(LOG_FILE, encoding="utf-8") as f:
        content = f.read()
    assert "[HTTP]" in content, "Missing [HTTP] log entries"
    assert "[TCP]" in content, "Missing [TCP] log entries"

    with open(LOG_FILE, encoding="utf-8") as f:
        before = f.read().splitlines()

    good = requests.get("http://127.0.0.1:8888/", headers={"X-Auth-Passcode": PASSCODE}, timeout=5)
    bad = requests.get("http://127.0.0.1:8888/", headers={"X-Auth-Passcode": "NOTTHEPASSCODE"}, timeout=5)
    assert good.status_code == 200 and bad.status_code == 403

    with socket.create_connection(("127.0.0.1", 8889), timeout=5) as s:
        s.sendall((PASSCODE + "\n").encode())
        assert s.recv(1024) == b"ACCESS_GRANTED\n"
    with socket.create_connection(("127.0.0.1", 8889), timeout=5) as s:
        s.sendall(b"NOTTHEPASSCODE\n")
        assert s.recv(1024) == b"DENIED\n"

    expected = ["[HTTP] 200", "[HTTP] 403", "[TCP] ACCESS_GRANTED", "[TCP] DENIED"]
    deadline = time.time() + 3
    added = []
    while time.time() < deadline:
        with open(LOG_FILE, encoding="utf-8") as f:
            now = f.read().splitlines()
        added = now[len(before):]
        if len(added) >= len(expected):
            break
        time.sleep(0.05)
    assert added == expected, f"Attempt log lines are not exact or one-per-attempt: {added!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
