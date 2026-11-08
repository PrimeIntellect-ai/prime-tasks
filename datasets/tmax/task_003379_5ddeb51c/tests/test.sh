#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import stat
import subprocess

BODY = b"Deploy v2 OK"
SOURCE = "/home/user/backend/src/main.rs"
SOCKET_PATH = "/home/user/nginx/backend.sock"


def proc_info():
    result = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        base = f"/proc/{name}"
        try:
            exe = os.path.realpath(f"{base}/exe")
            with open(f"{base}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            result.append((int(name), exe, argv))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def socket_owners(inode):
    owners = set()
    needle = f"socket:[{inode}]"
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == needle:
                        owners.add(int(name))
                except (FileNotFoundError, PermissionError):
                    pass
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def tcp_listener_owners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    owners = set()
    for inode in inodes:
        owners.update(socket_owners(inode))
    return owners


def unix_listener_owners(path):
    inodes = set()
    with open("/proc/net/unix") as f:
        next(f)
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[7] == path:
                inodes.add(fields[6])
    owners = set()
    for inode in inodes:
        owners.update(socket_owners(inode))
    return owners


def read_http(sock):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        assert chunk, "Connection closed before complete HTTP headers were received."
        data += chunk
        assert len(data) < 65536, "HTTP headers are unreasonably large."
    raw_headers, body = data.split(b"\r\n\r\n", 1)
    lines = raw_headers.split(b"\r\n")
    assert lines[0] == b"HTTP/1.1 200 OK", f"Unexpected status line: {lines[0]!r}"
    headers = {}
    for line in lines[1:]:
        assert b":" in line, f"Malformed HTTP header: {line!r}"
        key, value = line.split(b":", 1)
        headers[key.strip().lower()] = value.strip()
    assert headers.get(b"content-length") == str(len(BODY)).encode(), "Content-Length is missing or incorrect."
    expected = int(headers[b"content-length"])
    while len(body) < expected:
        chunk = sock.recv(4096)
        assert chunk, "Connection closed before the complete HTTP body was received."
        body += chunk
    assert body == BODY, f"Response body was {body!r}, expected {BODY!r}."


def request_tcp():
    with socket.create_connection(("127.0.0.1", 8888), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall(b"GET /verifier-live-check HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        read_http(sock)


def request_unix():
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(5)
        sock.connect(SOCKET_PATH)
        sock.sendall(b"GET /verifier-backend-check HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        read_http(sock)


def test_deploy_test_output():
    path = "/home/user/deploy_test.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "Deploy v2 OK", f"Content of {path} was '{content}', expected 'Deploy v2 OK'."
    with open(path, "rb") as f:
        assert f.read() == BODY, "deploy_test.txt is not the exact curl response body."


def test_nginx_running():
    result = subprocess.run(["ps", "-ef"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to execute ps command."
    processes = result.stdout.splitlines()
    nginx_running = any("nginx" in line and "/home/user/nginx/nginx.conf" in line for line in processes)
    assert nginx_running, "Nginx is not running or not loaded with /home/user/nginx/nginx.conf."

    info = {pid: (exe, argv) for pid, exe, argv in proc_info()}
    owners = tcp_listener_owners(8080)
    assert owners, "Nothing is listening on Nginx port 8080."
    assert any(info.get(pid, ("", []))[0].endswith("/nginx") for pid in owners), "Port 8080 is not owned by Nginx."
    assert any(exe.endswith("/nginx") and "/home/user/nginx/nginx.conf" in argv for exe, argv in info.values()), "No real Nginx process was started with the required configuration."


def test_ssh_tunnel_running():
    result = subprocess.run(["ps", "-ef"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to execute ps command."
    processes = result.stdout.splitlines()
    tunnel_running = any("8888:127.0.0.1:8080" in line for line in processes)
    assert tunnel_running, "SSH tunnel process identifiable by '8888:127.0.0.1:8080' is not running."

    info = {pid: (exe, argv) for pid, exe, argv in proc_info()}
    owners = tcp_listener_owners(8888)
    assert owners, "Nothing is listening on forwarded port 8888."
    valid = False
    for pid in owners:
        exe, argv = info.get(pid, ("", []))
        if exe.endswith("/ssh") and "-L" in argv and "8888:127.0.0.1:8080" in argv:
            valid = True
    assert valid, "Port 8888 is not owned by the required SSH local-forward process."


def test_rust_backend_source():
    assert os.path.isfile(SOURCE), f"Rust source file {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "UnixListener::bind" in content, f"Rust source in {SOURCE} is missing 'UnixListener::bind'."
    assert "Deploy v2 OK" in content, f"Rust source in {SOURCE} is missing the string 'Deploy v2 OK'."


def test_compiled_backend_is_running_on_unix_socket():
    assert os.path.exists(SOCKET_PATH), f"Backend socket {SOCKET_PATH} does not exist."
    owners = unix_listener_owners(SOCKET_PATH)
    assert owners, f"No process owns a listening Unix socket at {SOCKET_PATH}."

    info = {pid: (exe, argv) for pid, exe, argv in proc_info()}
    valid = []
    source_mtime = os.stat(SOURCE).st_mtime_ns
    for pid in owners:
        exe, _ = info.get(pid, ("", []))
        try:
            st = os.stat(exe)
            with open(exe, "rb") as f:
                elf = f.read(4) == b"\x7fELF"
            if stat.S_ISREG(st.st_mode) and elf and st.st_mtime_ns >= source_mtime:
                valid.append(exe)
        except (FileNotFoundError, PermissionError):
            pass
    assert valid, "The Unix socket is not owned by a current compiled ELF backend built after main.rs."
    request_unix()


def test_live_request_through_tunnel():
    request_tcp()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
