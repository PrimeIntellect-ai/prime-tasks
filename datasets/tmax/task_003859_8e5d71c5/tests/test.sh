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
import secrets
import subprocess
import tarfile
import time
from pathlib import Path

import pytest
import requests

TARBALL = "/home/user/nginx_backup.tar.gz"
CONFIG = "/home/user/nginx/nginx.conf"
SOCKET = "/tmp/app_backend.sock"
URL = "http://127.0.0.1:8080/"
EXPECTED_ORIGINAL_CONFIG = b'''worker_processes 1;
daemon off;
error_log /dev/stderr info;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /dev/stdout;
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;

    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://unix:/tmp/wrong.sock;
        }
    }
}
'''


def voicemail_values():
    result = subprocess.run(
        ["whisper", "/app/emergency_voicemail.wav"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
        check=True,
    )
    socket_match = re.search(r"(/[A-Za-z0-9_./-]+\.sock)\b", result.stdout)
    token_match = re.search(r"token is ([A-Za-z0-9_-]+)", result.stdout, re.I)
    assert socket_match, f"Could not derive socket path from voicemail transcript: {result.stdout!r}"
    assert token_match, f"Could not derive token from voicemail transcript: {result.stdout!r}"
    return socket_match.group(1), token_match.group(1).rstrip(".")


def request(path="/", token=None, timeout=5):
    headers = {"Connection": "close"}
    if token is not None:
        headers["Authorization"] = token
    return requests.get(URL.rstrip("/") + path, headers=headers, timeout=timeout)


def listening_tcp_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            if state != "0A":
                continue
            address, port = local.rsplit(":", 1)
            if port.upper() != "1F90":
                continue
            if address.upper() in ("0100007F", "00000000000000000000000001000000"):
                found.add(inode)
    return found


def processes_holding(inodes):
    holders = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            links = [os.readlink(fd) for fd in (proc / "fd").iterdir()]
            cmdline = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            exe = os.path.basename(os.readlink(proc / "exe"))
        except (OSError, PermissionError):
            continue
        held = {m.group(1) for link in links if (m := re.fullmatch(r"socket:\[(\d+)\]", link))}
        if held & inodes:
            holders.append((int(proc.name), exe, cmdline))
    return holders


def test_backup_tarball_exists_and_valid_and_contains_original_configuration():
    assert os.path.isfile(TARBALL), f"Backup tarball not found at {TARBALL}."
    try:
        with tarfile.open(TARBALL, "r:gz") as tar:
            members = tar.getmembers()
            assert len(members) > 0, "The backup tarball is empty."
            for member in members:
                normalized = os.path.normpath(member.name)
                assert not os.path.isabs(member.name) and normalized != ".." and not normalized.startswith("../"), \
                    f"Unsafe member in backup: {member.name}"
            configs = [m for m in members if m.isfile() and m.name.rstrip("/").endswith("nginx/nginx.conf")]
            assert configs, "Backup does not contain the original nginx/nginx.conf."
            assert any(tar.extractfile(m).read() == EXPECTED_ORIGINAL_CONFIG for m in configs), \
                "The archived nginx.conf is not the original pre-change configuration."
    except tarfile.ReadError:
        pytest.fail(f"The file at {TARBALL} is not a valid gzip-compressed tarball.")


def test_voicemail_values_and_effective_nginx_configuration():
    socket_path, token = voicemail_values()
    assert socket_path == SOCKET
    assert token == "alpha-tango-niner"
    assert os.path.isfile(CONFIG)
    checked = subprocess.run(
        ["nginx", "-t", "-c", CONFIG],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert checked.returncode == 0, checked.stdout
    dumped = subprocess.run(
        ["nginx", "-T", "-c", CONFIG],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
        check=True,
    ).stdout
    assert socket_path in dumped, "Effective NGINX configuration does not reference the voicemail socket."
    assert token in dumped, "Effective NGINX configuration does not contain the voicemail token."


def test_port_8080_is_really_owned_by_nginx_started_with_local_config():
    inodes = listening_tcp_inodes()
    assert inodes, "No process is listening on 127.0.0.1:8080."
    holders = processes_holding(inodes)
    assert any(exe == "nginx" for _, exe, _ in holders), \
        f"Port 8080 is not owned by an NGINX process: {holders!r}"

    nginx_cmdlines = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if os.path.basename(os.readlink(proc / "exe")) != "nginx":
                continue
            nginx_cmdlines.append((proc / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace"))
        except OSError:
            pass
    assert any("-c" in cmd and CONFIG in cmd for cmd in nginx_cmdlines), \
        f"NGINX was not started with -c {CONFIG}: {nginx_cmdlines!r}"


def test_backend_socket_and_daemon_are_running():
    assert os.path.exists(SOCKET), f"Backend socket {SOCKET} does not exist."
    socket_inode = None
    for line in Path("/proc/net/unix").read_text().splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 8 and fields[-1] == SOCKET:
            socket_inode = fields[6]
            break
    assert socket_inode, f"No live UNIX socket was found at {SOCKET}."
    holders = processes_holding({socket_inode})
    assert any(exe.startswith("python") and SOCKET in cmd for _, exe, cmd in holders), \
        f"The expected backend daemon is not holding {SOCKET}: {holders!r}"
    assert os.access("/home/user/init_backend.sh", os.X_OK), "The custom init script is missing or not executable."


def test_nginx_authorized_request():
    response = request("/", "Bearer alpha-tango-niner")
    assert response.status_code == 200, f"Expected HTTP 200 OK with correct token, but got {response.status_code}."


def test_nginx_unauthorized_request_missing_header():
    response = request("/")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized with missing token, but got {response.status_code}."


def test_nginx_unauthorized_request_invalid_token():
    response = request("/", "Bearer wrong-token")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized with incorrect token, but got {response.status_code}."


def test_authorization_on_unpredictable_requests():
    _, token = voicemail_values()
    for _ in range(4):
        path = "/probe-" + secrets.token_hex(12) + "?q=" + secrets.token_hex(8)
        assert request(path, "Bearer " + token).status_code == 200
        assert request(path).status_code == 401
        assert request(path, "Bearer " + secrets.token_hex(20)).status_code == 401
    for malformed in (token, "bearer " + token, "Bearer  " + token, "Bearer " + token + "-extra"):
        assert request("/auth-shape-" + secrets.token_hex(8), malformed).status_code == 401


def test_nginx_actually_proxies_to_required_unix_socket():
    _, token = voicemail_values()
    moved = SOCKET + ".verifier-" + secrets.token_hex(8)
    os.rename(SOCKET, moved)
    try:
        response = request("/socket-dependency-" + secrets.token_hex(12), "Bearer " + token)
        assert response.status_code in (502, 504), \
            f"Authorized request still returned {response.status_code} after required upstream socket was removed."
        assert response.headers.get("Server", "").lower().startswith("nginx"), \
            "Failure response was not produced by NGINX."
    finally:
        if os.path.lexists(SOCKET):
            os.unlink(SOCKET)
        os.rename(moved, SOCKET)

    deadline = time.time() + 5
    while True:
        response = request("/socket-restored-" + secrets.token_hex(8), "Bearer " + token)
        if response.status_code == 200:
            break
        assert time.time() < deadline, f"Service did not recover after restoring socket; last status {response.status_code}."
        time.sleep(0.1)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
