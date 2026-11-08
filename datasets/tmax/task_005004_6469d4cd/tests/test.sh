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
import json
import os
import pty
import select
import shutil
import signal
import time

import pytest
import requests

EXPECTED_IP = "172.16.4.88"
EXPECTED_PASSWORD = "B@ckD00r_77Xq"
EXPECTED_REPORT = {
    "attacker_ip": EXPECTED_IP,
    "backdoor_password": EXPECTED_PASSWORD,
}


def test_required_files():
    ip_path = "/home/user/attacker_ip.txt"
    password_path = "/home/user/attacker_password.txt"
    report_path = "/home/user/report.json"
    config_path = "/home/user/sshd_config"

    for path in (ip_path, password_path, report_path, config_path):
        assert os.path.isfile(path), f"Required file is missing or not a regular file: {path}"

    with open(ip_path, "r", encoding="utf-8") as f:
        assert f.read().strip() == EXPECTED_IP

    with open(password_path, "r", encoding="utf-8") as f:
        assert f.read().strip() == EXPECTED_PASSWORD

    with open(report_path, "r", encoding="utf-8") as f:
        try:
            report = json.load(f)
        except ValueError as e:
            pytest.fail(f"{report_path} is not valid JSON: {e}")
    assert report == EXPECTED_REPORT, f"Unexpected on-disk report: {report!r}"

    assert os.path.getsize(config_path) > 0, f"{config_path} must not be empty"


def test_http_report():
    url = "http://127.0.0.1:8080/report.json"
    try:
        resp = requests.get(url, timeout=5)
        resp.raise_for_status()
    except Exception as e:
        pytest.fail(f"Failed to connect to HTTP server or fetch {url}: {e}")

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON. Content: {resp.text}")

    assert data.get("attacker_ip") == EXPECTED_IP, \
        f"Expected attacker_ip '{EXPECTED_IP}', got '{data.get('attacker_ip')}'"
    assert data.get("backdoor_password") == EXPECTED_PASSWORD, \
        f"Expected backdoor_password '{EXPECTED_PASSWORD}', got '{data.get('backdoor_password')}'"
    assert data == EXPECTED_REPORT, f"HTTP report has unexpected fields or values: {data!r}"


def _paramiko_authenticates(username, password):
    import paramiko

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(
            "127.0.0.1",
            port=8022,
            username=username,
            password=password,
            timeout=5,
            banner_timeout=5,
            auth_timeout=5,
            allow_agent=False,
            look_for_keys=False,
        )
        return True
    except Exception:
        return False
    finally:
        client.close()


def _openssh_authenticates(username, password):
    if shutil.which("ssh") is None:
        pytest.fail("Neither paramiko nor the ssh client is available to test authentication")

    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("ssh", [
            "ssh", "-vv",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "PubkeyAuthentication=no",
            "-o", "PreferredAuthentications=password,keyboard-interactive",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "ConnectTimeout=5",
            "-p", "8022",
            f"{username}@127.0.0.1",
            "true",
        ])

    output = b""
    password_sent = False
    deadline = time.time() + 10
    status = None
    try:
        while time.time() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.2)
            if ready:
                try:
                    chunk = os.read(fd, 4096)
                except OSError:
                    chunk = b""
                if chunk:
                    output += chunk
                    if b"password:" in output.lower() and not password_sent:
                        os.write(fd, password.encode() + b"\n")
                        password_sent = True

            waited, status = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                break
        else:
            os.kill(pid, signal.SIGKILL)
            _, status = os.waitpid(pid, 0)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass

    text = output.decode(errors="ignore")
    return "Authenticated to 127.0.0.1" in text


def test_ssh_honeypot_accepts_only_required_credentials():
    try:
        import paramiko  # noqa: F401
        authenticates = _paramiko_authenticates
    except ImportError:
        authenticates = _openssh_authenticates

    assert authenticates("admin", EXPECTED_PASSWORD), \
        "SSH connection failed with the required username and password"
    assert not authenticates("admin", "definitely-wrong-password"), \
        "SSH honeypot accepted an incorrect password"
    assert not authenticates("not-admin", EXPECTED_PASSWORD), \
        "SSH honeypot accepted an incorrect username"
    assert authenticates("admin", EXPECTED_PASSWORD), \
        "SSH honeypot stopped accepting the required credentials after rejected attempts"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
