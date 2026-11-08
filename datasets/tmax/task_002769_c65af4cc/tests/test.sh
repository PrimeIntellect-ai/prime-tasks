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
import socket
import time
import requests
import pytest

MAIL_LOG = "/home/user/mail.log"
INITIAL_MAIL_EXISTS = os.path.isfile(MAIL_LOG)
if INITIAL_MAIL_EXISTS:
    with open(MAIL_LOG, "r", errors="replace") as f:
        INITIAL_MAIL_CONTENT = f.read()
else:
    INITIAL_MAIL_CONTENT = ""


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def proc_ppid(pid):
    try:
        with open(f"/proc/{pid}/status", "r") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return 0


def process_lineage(pid):
    result = []
    seen = set()
    while pid > 0 and pid not in seen:
        seen.add(pid)
        result.append((pid, proc_cmdline(pid)))
        pid = proc_ppid(pid)
    return result


def socket_inodes_for_tcp_port(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass
    return inodes


def socket_inodes_for_unix_path(path):
    inodes = set()
    try:
        with open("/proc/net/unix", "r") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 8 and fields[-1] == path:
                    inodes.add(fields[6])
    except OSError:
        pass
    return inodes


def pids_holding_inodes(inodes):
    owners = set()
    if not inodes:
        return owners
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        owners.add(int(entry))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def test_required_artifacts_and_processes():
    config_path = "/home/user/nginx.conf"
    backend_path = "/home/user/backend.sh"

    assert os.path.isfile(config_path), f"Missing required Nginx config: {config_path}"
    assert os.path.isfile(backend_path), f"Missing required backend script: {backend_path}"
    assert os.access(backend_path, os.X_OK), "backend.sh is not executable"

    with open(config_path, "r", errors="replace") as f:
        config = f.read()
    with open(backend_path, "r", errors="replace") as f:
        backend = f.read()

    assert "/tmp/wrong_path.sock" not in config, "nginx.conf still uses the original mismatched socket"
    proxy_matches = re.findall(r"proxy_pass\s+http://unix:([^;\s]+)", config)
    assert proxy_matches, "nginx.conf does not proxy to a Unix socket"
    proxy_socket = proxy_matches[0].rstrip(":")
    assert proxy_socket in backend, "backend.sh and nginx.conf do not use the same Unix socket path"
    assert "charlie" in backend and "ocean" in backend, "backend.sh was not configured for the requested account"
    assert "Not Implemented" not in backend, "backend.sh still contains the original placeholder response"

    nginx_owners = pids_holding_inodes(socket_inodes_for_tcp_port(8080))
    assert nginx_owners, "Nothing is listening on TCP port 8080"
    nginx_lineages = [process_lineage(pid) for pid in nginx_owners]
    assert any(
        any("nginx" in cmd.lower() for _, cmd in lineage)
        and any("/home/user/nginx.conf" in cmd for _, cmd in lineage)
        for lineage in nginx_lineages
    ), "Port 8080 is not owned by Nginx started with /home/user/nginx.conf"

    backend_owners = pids_holding_inodes(socket_inodes_for_unix_path(proxy_socket))
    assert backend_owners, f"No running backend owns the configured socket {proxy_socket}"
    backend_lineages = [process_lineage(pid) for pid in backend_owners]
    assert any(
        any("/home/user/backend.sh" in cmd for _, cmd in lineage)
        for lineage in backend_lineages
    ), "The configured Unix socket is not being served by /home/user/backend.sh"

    smtp_owners = pids_holding_inodes(socket_inodes_for_tcp_port(8025))
    assert smtp_owners, "Nothing is listening on TCP port 8025"
    smtp_lineages = [process_lineage(pid) for pid in smtp_owners]
    assert any(
        any("bash" in cmd.lower() for _, cmd in lineage)
        for lineage in smtp_lineages
    ), "The SMTP listener on port 8025 is not bash-based"


def test_http_service():
    """Verify that Nginx returns the correct profile response."""
    url = "http://127.0.0.1:8080/profile/charlie"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    expected_body = "User: charlie, Secret: ocean"
    assert response.text.strip() == expected_body, f"Expected body '{expected_body}', got '{response.text}'"


def test_welcome_email_sent_before_verification():
    """Verify that an initial email was already logged before verifier traffic."""
    assert INITIAL_MAIL_EXISTS, f"mail.log is missing at {MAIL_LOG}, meaning no welcome email was logged."
    assert len(INITIAL_MAIL_CONTENT.strip()) > 0, "mail.log was empty before verification. Expected an initial welcome email."


def test_smtp_service():
    """Verify that SMTP accepts standard commands and logs the verifier message."""
    host = "127.0.0.1"
    port = 8025

    try:
        s = socket.create_connection((host, port), timeout=5)
    except OSError as e:
        pytest.fail(f"Failed to connect to SMTP service at {host}:{port}: {e}")

    with s:
        greeting = s.recv(1024).decode(errors="replace")
        assert greeting.startswith("2"), f"Expected SMTP greeting, got: {greeting}"

        def send_cmd(cmd):
            s.sendall(cmd.encode() + b"\r\n")
            time.sleep(0.1)
            return s.recv(1024).decode(errors="replace")

        resp = send_cmd("HELO verifier")
        assert resp.startswith("2"), f"Expected 2xx response for HELO, got: {resp}"

        resp = send_cmd("MAIL FROM:<admin@localhost>")
        assert resp.startswith("2"), f"Expected 2xx response for MAIL FROM, got: {resp}"

        resp = send_cmd("RCPT TO:<charlie@localhost>")
        assert resp.startswith("2"), f"Expected 2xx response for RCPT TO, got: {resp}"

        resp = send_cmd("DATA")
        assert resp.startswith("354"), f"Expected 354 response for DATA, got: {resp}"

        test_msg = "Subject: Test\n\nThis is a test message from the verifier."
        s.sendall(test_msg.encode() + b"\r\n.\r\n")
        time.sleep(0.2)
        resp = s.recv(1024).decode(errors="replace")
        assert resp.startswith("2"), f"Expected 2xx response after DATA payload, got: {resp}"

        send_cmd("QUIT")

    assert os.path.isfile(MAIL_LOG), f"mail.log was not created at {MAIL_LOG}"
    with open(MAIL_LOG, "r", errors="replace") as f:
        log_content = f.read()
    assert "This is a test message from the verifier." in log_content, "The test message body was not found in mail.log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
