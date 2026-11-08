#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import math
import os
import socket
import struct
import subprocess
import time
import pytest

PROJECT_DIR = "/home/user/math_ws_server"
LOG_PATH = "/home/user/ws_output.log"


def expected_solutions(r):
    if r < 0:
        return []
    result = []
    for x in range(math.isqrt(r) + 1):
        y2 = r - x * x
        y = math.isqrt(y2)
        if y * y == y2:
            result.append([x, y])
    return result


def recv_exact(sock, count):
    data = b""
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise AssertionError("WebSocket connection closed unexpectedly")
        data += chunk
    return data


def send_frame(sock, opcode, payload=b""):
    if isinstance(payload, str):
        payload = payload.encode("utf-8")
    mask = os.urandom(4)
    length = len(payload)
    header = bytes([0x80 | opcode])
    if length < 126:
        header += bytes([0x80 | length])
    elif length < 65536:
        header += bytes([0x80 | 126]) + struct.pack("!H", length)
    else:
        header += bytes([0x80 | 127]) + struct.pack("!Q", length)
    masked = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))
    sock.sendall(header + mask + masked)


def recv_frame(sock):
    first, second = recv_exact(sock, 2)
    opcode = first & 0x0f
    length = second & 0x7f
    if length == 126:
        length = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(sock, 8))[0]
    mask = recv_exact(sock, 4) if second & 0x80 else None
    payload = recv_exact(sock, length)
    if mask:
        payload = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))
    return opcode, payload


def recv_text(sock):
    fragments = []
    while True:
        opcode, payload = recv_frame(sock)
        if opcode == 0x8:
            raise AssertionError("Server closed the WebSocket before responding")
        if opcode == 0x9:
            send_frame(sock, 0xA, payload)
            continue
        if opcode in (0x1, 0x0):
            fragments.append(payload)
            # Warp sends these small responses as one complete text frame.
            return b"".join(fragments).decode("utf-8")


def open_websocket():
    sock = socket.create_connection(("127.0.0.1", 8080), timeout=3)
    sock.settimeout(3)
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        "GET /solve HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    )
    sock.sendall(request.encode("ascii"))
    response = b""
    while b"\r\n\r\n" not in response:
        response += sock.recv(4096)
        assert len(response) < 65536, "Oversized WebSocket handshake response"
    header = response.decode("latin1").lower()
    expected_accept = base64.b64encode(
        hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
    ).decode("ascii").lower()
    assert header.startswith("http/1.1 101"), f"/solve did not upgrade to WebSocket: {header!r}"
    assert f"sec-websocket-accept: {expected_accept}" in header, "Invalid WebSocket accept header"
    return sock


def listener_pids():
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_addr, state = fields[1], fields[3]
            host_hex, port_hex = local_addr.split(":")
            if host_hex == "0100007F" and int(port_hex, 16) == 8080 and state == "0A":
                inodes.add(fields[9])
    pids = []
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
                    pids.append(int(entry))
                    break
        except OSError:
            continue
    return pids


def test_rust_compiles():
    assert os.path.isdir(PROJECT_DIR), f"Project directory {PROJECT_DIR} does not exist."
    result = subprocess.run(
        ["cargo", "check"], cwd=PROJECT_DIR, capture_output=True, text=True
    )
    assert result.returncode == 0, f"Rust project failed to compile:\n{result.stderr}"


def test_compiled_server_is_running():
    pids = listener_pids()
    assert pids, "No process is listening on 127.0.0.1:8080"
    executables = []
    for pid in pids:
        try:
            executables.append(os.path.basename(os.readlink(f"/proc/{pid}/exe")).replace(" (deleted)", ""))
        except OSError:
            pass
    assert "math_ws_server" in executables, (
        "Port 8080 is not owned by the compiled math_ws_server executable; "
        f"listener executables were {executables}"
    )


def test_live_websocket_and_solver():
    sock = open_websocket()
    try:
        # Invalid input must be ignored without killing the connection.
        send_frame(sock, 0x1, "{not valid json")
        sock.settimeout(0.4)
        try:
            opcode, payload = recv_frame(sock)
            if opcode == 0x9:
                send_frame(sock, 0xA, payload)
            elif opcode == 0x8:
                pytest.fail("Server closed the connection instead of ignoring invalid input")
            else:
                pytest.fail(f"Server responded to invalid input with opcode {opcode}: {payload!r}")
        except socket.timeout:
            pass
        finally:
            sock.settimeout(3)

        # Include edge cases plus values selected only when verification runs.
        values = [-7, 0, 1, 2, 3, 50, 325]
        random_bytes = os.urandom(24)
        for i in range(0, len(random_bytes), 4):
            a = 1 + random_bytes[i] % 180
            b = random_bytes[i + 1] % 180
            if random_bytes[i + 2] & 1:
                r = a * a + b * b
            else:
                r = 1 + int.from_bytes(random_bytes[i:i + 4], "big") % 50000
            values.append(r)

        for r in values:
            send_frame(sock, 0x1, json.dumps({"r": r}, separators=(",", ":")))
            raw = recv_text(sock)
            try:
                actual = json.loads(raw)
            except json.JSONDecodeError as exc:
                pytest.fail(f"Server returned invalid JSON for r={r}: {raw!r} ({exc})")
            expected = expected_solutions(r)
            assert actual == expected, f"Incorrect /solve response for r={r}: expected {expected}, got {actual}"
    finally:
        try:
            send_frame(sock, 0x8)
        except OSError:
            pass
        sock.close()


def test_ws_output_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines of output in {LOG_PATH}, found {len(lines)}."
    expected_outputs = [
        [[0, 5], [3, 4], [4, 3], [5, 0]],
        [[1, 8], [4, 7], [7, 4], [8, 1]],
        [[4, 33], [9, 32], [12, 31], [23, 24], [24, 23], [31, 12], [32, 9], [33, 4]],
    ]
    try:
        parsed_lines = [json.loads(line) for line in lines]
    except json.JSONDecodeError as exc:
        pytest.fail(f"Failed to parse JSON from {LOG_PATH}: {exc}")
    for i, (actual, expected) in enumerate(zip(parsed_lines, expected_outputs)):
        assert actual == expected, f"Mismatch on line {i + 1}. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
