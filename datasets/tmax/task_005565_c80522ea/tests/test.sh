#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import re
import socket
import stat
from pathlib import Path

LOG_PATH = "/home/user/restore_success.log"
APP_PATH = "/home/user/restore/app/target/release/mailgate"
APP_DIR = "/home/user/restore/app"
NGINX_CONFIG = "/home/user/nginx.conf"
EXPECTED = b"MAILGATE_RESTORE_V1_OK\n"


def processes():
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            exe = os.path.realpath(entry / "exe")
            yield int(entry.name), exe, cmdline
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue


def process_socket_inodes(pid):
    result = set()
    fd_dir = Path(f"/proc/{pid}/fd")
    try:
        entries = list(fd_dir.iterdir())
    except (FileNotFoundError, PermissionError):
        return result
    for fd in entries:
        try:
            target = os.readlink(fd)
        except (FileNotFoundError, PermissionError, OSError):
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            result.add(match.group(1))
    return result


def unix_socket_inode(path):
    with open("/proc/net/unix", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[7] == path:
                # A listening Unix stream socket has the listening flag set.
                if fields[3] == "00010000" and fields[4] == "0001":
                    return fields[6]
    return None


def tcp_listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def request_unix(path):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    try:
        sock.connect(path)
        sock.sendall(b"GET /health HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        sock.close()
    raw = b"".join(chunks)
    header, separator, body = raw.partition(b"\r\n\r\n")
    assert separator, "Rust backend did not return a valid HTTP response"
    status_line = header.split(b"\r\n", 1)[0]
    assert re.match(br"HTTP/\d(?:\.\d)? 200(?: |$)", status_line), status_line
    return body


def test_restore_success_log_and_live_deployment():
    # Preserve the original exact verification-file assertion.
    assert os.path.exists(LOG_PATH), f"Expected verification file {LOG_PATH} does not exist."
    with open(LOG_PATH, "rb") as f:
        content = f.read()
    assert content == EXPECTED, (
        f"File {LOG_PATH} does not contain the exact expected output.\n"
        f"Expected: {EXPECTED!r}\nGot: {content!r}"
    )

    # The required release artifact must be a current executable ELF build.
    assert os.path.isfile(APP_PATH), f"Missing release binary: {APP_PATH}"
    assert os.access(APP_PATH, os.X_OK), f"Release binary is not executable: {APP_PATH}"
    with open(APP_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mailgate release artifact is not an ELF executable"
    inputs = [Path(APP_DIR) / "Cargo.toml", *Path(APP_DIR).glob("src/**/*.rs")]
    assert inputs and all(p.exists() for p in inputs), "Rust build inputs are missing"
    assert os.path.getmtime(APP_PATH) >= max(p.stat().st_mtime for p in inputs), (
        "Release binary is older than the Rust build inputs"
    )

    proc_list = list(processes())
    backend_pids = []
    for pid, _, _ in proc_list:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", APP_PATH):
                backend_pids.append(pid)
        except (FileNotFoundError, PermissionError, OSError):
            pass
    assert backend_pids, "The required mailgate release binary is not running"

    # Confirm the configured upstream is a live Unix socket owned by mailgate.
    config = Path(NGINX_CONFIG).read_text()
    matches = re.findall(r"proxy_pass\s+http://unix:([^;\s]+)\s*;", config)
    assert matches, "Nginx config has no Unix-socket proxy_pass upstream"
    socket_path = matches[0]
    assert os.path.isabs(socket_path), "Configured upstream socket path is not absolute"
    assert os.path.exists(socket_path), f"Configured upstream socket does not exist: {socket_path}"
    assert stat.S_ISSOCK(os.stat(socket_path).st_mode), f"Upstream path is not a socket: {socket_path}"
    upstream_inode = unix_socket_inode(socket_path)
    assert upstream_inode is not None, f"Configured upstream is not a listening Unix socket: {socket_path}"
    assert any(upstream_inode in process_socket_inodes(pid) for pid in backend_pids), (
        "The configured upstream socket is not owned by the running mailgate binary"
    )

    # Confirm Nginx was started with the provided config and owns port 8080.
    nginx_pids = []
    configured_nginx = False
    for pid, exe, cmdline in proc_list:
        if os.path.basename(exe) == "nginx":
            nginx_pids.append(pid)
            if NGINX_CONFIG in cmdline:
                configured_nginx = True
    assert configured_nginx, "No running Nginx process was started with /home/user/nginx.conf"
    listener_inodes = tcp_listener_inodes(8080)
    assert listener_inodes, "Nothing is listening on TCP port 8080"
    assert any(listener_inodes & process_socket_inodes(pid) for pid in nginx_pids), (
        "The listener on port 8080 is not owned by Nginx"
    )

    # Exercise both the backend artifact and the externally visible Nginx endpoint.
    backend_body = request_unix(socket_path)
    assert backend_body == EXPECTED, f"Unexpected direct backend response: {backend_body!r}"

    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=5)
    try:
        conn.request("GET", "/health")
        response = conn.getresponse()
        proxy_body = response.read()
    finally:
        conn.close()
    assert response.status == 200, f"Nginx /health returned HTTP {response.status}"
    assert proxy_body == backend_body, (
        f"Nginx response {proxy_body!r} differs from backend response {backend_body!r}"
    )
    assert content == proxy_body, "restore_success.log is not the raw live /health response body"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
