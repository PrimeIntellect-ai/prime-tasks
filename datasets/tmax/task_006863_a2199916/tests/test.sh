#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import json
import os
import secrets
import socket
import subprocess
import zlib

import pytest
import websockets

PROJECT = "/home/user/ws-ingest"
BINARY = "/home/user/ws-ingest/target/debug/ws-ingest"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def pid_uses_executable(pid, executable):
    try:
        return os.path.samefile(f"/proc/{pid}/exe", executable)
    except (FileNotFoundError, PermissionError, OSError):
        return False


def test_rust_code_fixed():
    # Keep the original source-level assertions.
    main_path = "/home/user/ws-ingest/src/main.rs"
    assert os.path.isfile(main_path), f"{main_path} is missing."
    with open(main_path, "r") as f:
        main_content = f.read()
    assert ".await" in main_content and "ws_stream.next()" in main_content, "The missing .await bug in main.rs was not fixed."

    parser_path = "/home/user/ws-ingest/src/parser.rs"
    assert os.path.isfile(parser_path), f"{parser_path} is missing."
    with open(parser_path, "r") as f:
        parser_content = f.read()
    assert "u32" in parser_content and "String" not in parser_content.split("pub checksum:")[1].split(",")[0], "The checksum type in parser.rs was not changed to u32."

    checksum_path = "/home/user/ws-ingest/src/checksum.rs"
    assert os.path.isfile(checksum_path), f"{checksum_path} is missing."
    with open(checksum_path, "r") as f:
        checksum_content = f.read()
    assert "as_bytes()" in checksum_content, "The hasher.update call in checksum.rs was not fixed to use .as_bytes()."

    result = subprocess.run(
        ["cargo", "build"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
    )
    assert result.returncode == 0, f"cargo build failed:\n{result.stdout}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Cargo did not produce the ws-ingest executable."


def test_nginx_config():
    proxy_conf_path = "/home/user/proxy.conf"
    assert os.path.isfile(proxy_conf_path), f"Nginx config {proxy_conf_path} is missing."
    with open(proxy_conf_path, "r") as f:
        content = f.read()

    assert "127.0.0.1:8080" in content or " 8080" in content, "Nginx is not configured to listen on port 8080."
    assert "proxy_pass" in content and "9090" in content, "Nginx is not configured to proxy_pass to port 9090."
    assert "Upgrade" in content, "Nginx is not configured to handle WebSocket Upgrade headers."

    result = subprocess.run(
        ["nginx", "-t", "-c", proxy_conf_path], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert result.returncode == 0, f"Nginx rejected proxy.conf:\n{result.stdout}"


def test_services_running():
    # Keep the original TCP-listener assertions.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        result = s.connect_ex(("127.0.0.1", 9090))
        assert result == 0, "The Rust WebSocket server is not listening on 127.0.0.1:9090."

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1)
        result = s.connect_ex(("127.0.0.1", 8080))
        assert result == 0, "The Nginx reverse proxy is not listening on 127.0.0.1:8080."

    backend_pids = listener_pids(9090)
    assert backend_pids, "Could not identify the process listening on port 9090."
    assert any(pid_uses_executable(pid, BINARY) for pid in backend_pids), \
        "Port 9090 is not served by the built ws-ingest executable."

    nginx_pids = listener_pids(8080)
    assert nginx_pids, "Could not identify the process listening on port 8080."
    assert any(pid_uses_executable(pid, "/usr/sbin/nginx") for pid in nginx_pids), \
        "Port 8080 is not served by Nginx."

    configured = False
    for pid in nginx_pids:
        if not pid_uses_executable(pid, "/usr/sbin/nginx"):
            continue
        try:
            cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ")
            if b"/home/user/proxy.conf" in cmdline:
                configured = True
        except OSError:
            pass
    assert configured, "The running Nginx instance was not started with /home/user/proxy.conf."


async def websocket_exchange(uri, payload):
    async with websockets.connect(uri, open_timeout=3, close_timeout=2) as ws:
        await ws.send(payload)
        return await asyncio.wait_for(ws.recv(), timeout=3)


def test_live_websocket_stack():
    # Generate the expected checksums in the verifier rather than trusting a log.
    data = "verifier_" + secrets.token_hex(16)
    checksum = zlib.crc32(data.encode("utf-8")) & 0xFFFFFFFF
    valid = json.dumps({"data": data, "checksum": checksum})

    direct = asyncio.run(websocket_exchange("ws://127.0.0.1:9090", valid))
    assert direct == "SUCCESS: Checksum verified", f"Backend returned an unexpected response: {direct!r}"

    proxied = asyncio.run(websocket_exchange("ws://127.0.0.1:8080", valid))
    assert proxied == "SUCCESS: Checksum verified", f"Proxied WebSocket returned an unexpected response: {proxied!r}"

    wrong = json.dumps({"data": data, "checksum": (checksum + 1) & 0xFFFFFFFF})
    response = asyncio.run(websocket_exchange("ws://127.0.0.1:8080", wrong))
    assert response == "ERROR: Invalid checksum", f"Invalid checksum was not rejected: {response!r}"

    response = asyncio.run(websocket_exchange("ws://127.0.0.1:8080", "not valid json"))
    assert response == "ERROR: Invalid JSON", f"Malformed JSON was not rejected: {response!r}"


def test_python_script_exists_and_runs():
    script_path = "/home/user/test_ws.py"
    assert os.path.isfile(script_path), f"The Python test script {script_path} is missing."
    with open(script_path, "r") as f:
        script = f.read()
    assert "ws://127.0.0.1:8080" in script, "The Python script does not connect to the proxy."
    assert "e2e_system_check" in script, "The Python script does not use the required data value."

    log_path = "/home/user/test_result.log"
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ["python3", script_path], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    assert result.returncode == 0, f"The Python end-to-end test failed:\n{result.stdout}"
    assert os.path.isfile(log_path), "The Python script did not create /home/user/test_result.log."


def test_result_log():
    log_path = "/home/user/test_result.log"
    assert os.path.isfile(log_path), f"The test result log {log_path} is missing. Did the Python script run successfully?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "SUCCESS: Checksum verified" in content, f"The test result log does not contain the expected success message. Found: {content}"
    assert content == "SUCCESS: Checksum verified", f"The result log is not the raw expected server response. Found: {content!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
