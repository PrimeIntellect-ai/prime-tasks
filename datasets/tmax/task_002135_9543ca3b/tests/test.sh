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
import re
import secrets
import socket
import stat
import subprocess

import pytest
import requests

URL = "http://127.0.0.1:8080/api/status"
SECRET = "X89F-SYS-BETA"
SOCK_PATH = "/home/user/backend/sockets/api.sock"
NGINX_CONF = "/home/user/nginx/nginx.conf"


def proc_socket_owners(inodes):
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def listening_tcp_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def unix_socket_inodes(path):
    result = set()
    with open("/proc/net/unix") as f:
        next(f)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[7] == path:
                result.add(fields[6])
    return result


def proc_text(pid, name):
    try:
        with open(f"/proc/{pid}/{name}", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def unix_http_request(auth):
    marker = secrets.token_hex(12)
    request = (
        f"GET /api/status?probe={marker} HTTP/1.1\r\n"
        "Host: localhost\r\n"
        f"Authorization: Bearer {auth}\r\n"
        "Connection: close\r\n\r\n"
    ).encode()
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(5)
    try:
        client.connect(SOCK_PATH)
        client.sendall(request)
        chunks = []
        while True:
            chunk = client.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        client.close()
    raw = b"".join(chunks)
    head, sep, body = raw.partition(b"\r\n\r\n")
    assert sep, f"Backend socket returned a malformed HTTP response: {raw!r}"
    status_line = head.split(b"\r\n", 1)[0].decode(errors="replace")
    match = re.match(r"HTTP/\d(?:\.\d)?\s+(\d+)", status_line)
    assert match, f"Backend socket returned an invalid status line: {status_line!r}"
    return int(match.group(1)), body


def test_api_status_success():
    try:
        response = requests.get(URL, headers={"Authorization": f"Bearer {SECRET}"}, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to Nginx at {URL}: {exc}")
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert data.get("status") == "operational", f"Expected JSON payload {{'status': 'operational'}}, got {data}"


def test_api_status_forbidden():
    try:
        response = requests.get(URL, headers={"Authorization": "Bearer INVALID_TOKEN"}, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to Nginx at {URL}: {exc}")
    assert response.status_code == 403, f"Expected HTTP 403 Forbidden for invalid token, got {response.status_code}. Response: {response.text}"


def test_socket_exists_and_is_socket():
    assert os.path.exists(SOCK_PATH), f"Expected Unix socket at {SOCK_PATH} does not exist. Did the backend start and create it?"
    assert stat.S_ISSOCK(os.stat(SOCK_PATH).st_mode), f"File at {SOCK_PATH} exists but is not a Unix domain socket."


def test_nginx_is_running_with_requested_config_and_owns_port():
    tcp_inodes = listening_tcp_inodes(8080)
    assert tcp_inodes, "No process is listening on TCP port 8080"
    owners = proc_socket_owners(tcp_inodes)
    assert owners, "Could not identify the process listening on TCP port 8080"
    nginx_owners = [pid for pid in owners if proc_text(pid, "comm").strip().startswith("nginx")]
    assert nginx_owners, f"Port 8080 is not owned by Nginx; listener PIDs were {sorted(owners)}"

    nginx_pids = [int(pid) for pid in os.listdir("/proc") if pid.isdigit() and proc_text(int(pid), "comm").strip().startswith("nginx")]
    command_lines = [proc_text(pid, "cmdline") for pid in nginx_pids]
    assert any("-c /home/user/nginx/nginx.conf" in cmd or "-c  /home/user/nginx/nginx.conf" in cmd for cmd in command_lines), \
        f"No running Nginx process was started with {NGINX_CONF}"


def test_loaded_nginx_config_proxies_to_required_unix_socket():
    result = subprocess.run(
        ["nginx", "-T", "-c", NGINX_CONF],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Nginx rejected the requested configuration:\n{result.stdout}"
    config = re.sub(r"#.*", "", result.stdout)
    assert re.search(r"listen\s+(?:127\.0\.0\.1:)?8080\s*;", config), "Loaded Nginx configuration does not listen on port 8080"
    assert re.search(r"location\s+(?:\^~\s+)?/api/\s*\{", config), "Loaded Nginx configuration has no /api/ location"
    direct_unix_proxy = re.search(
        r"proxy_pass\s+http://unix:/home/user/backend/sockets/api\.sock(?::[^;]*)?\s*;",
        config,
    )
    assert direct_unix_proxy, f"The loaded Nginx configuration does not proxy_pass /api/ to unix:{SOCK_PATH}"
    assert "127.0.0.1:9000" not in config, "The stale TCP backend target 127.0.0.1:9000 is still loaded"


def test_backend_really_serves_the_unix_socket_with_required_environment():
    inodes = unix_socket_inodes(SOCK_PATH)
    assert inodes, f"No live Unix listener was found for {SOCK_PATH}"
    owners = proc_socket_owners(inodes)
    assert owners, f"No running process owns the Unix socket {SOCK_PATH}"

    valid_owner = False
    for pid in owners:
        cmd = proc_text(pid, "cmdline")
        env = proc_text(pid, "environ")
        exe = ""
        try:
            exe = os.readlink(f"/proc/{pid}/exe")
        except OSError:
            pass
        is_backend = ("backend.py" in cmd) or ("gunicorn" in cmd and "backend" in cmd)
        if ("python" in exe or "python" in cmd or "gunicorn" in cmd) and is_backend and \
                "API_SECRET=X89F-SYS-BETA" in env and f"SOCKET_PATH={SOCK_PATH}" in env:
            valid_owner = True
            break
    assert valid_owner, "The socket is not owned by the requested Python backend with API_SECRET and SOCKET_PATH set"

    status, body = unix_http_request(SECRET)
    assert status == 200, f"Direct request through the backend Unix socket returned HTTP {status}"
    try:
        payload = json.loads(body)
    except ValueError:
        pytest.fail(f"Backend Unix socket returned invalid JSON: {body!r}")
    assert payload.get("status") == "operational", f"Unexpected direct backend payload: {payload}"

    random_bad_secret = "INVALID-" + secrets.token_hex(16)
    status, _ = unix_http_request(random_bad_secret)
    assert status == 403, f"Backend Unix socket accepted a randomized invalid credential with HTTP {status}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
