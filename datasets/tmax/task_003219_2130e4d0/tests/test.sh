#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import base64
import subprocess
import time
import pytest


def fletcher16(data):
    sum1 = 0
    sum2 = 0
    for byte in data:
        sum1 = (sum1 + byte) % 255
        sum2 = (sum2 + sum1) % 255
    return (sum2 << 8) | sum1


def recv_exact(sock, length):
    chunks = bytearray()
    while len(chunks) < length:
        chunk = sock.recv(length - len(chunks))
        if not chunk:
            raise RuntimeError("WebSocket connection closed unexpectedly")
        chunks.extend(chunk)
    return bytes(chunks)


def recv_websocket_payload(sock):
    header = recv_exact(sock, 2)
    payload_len = header[1] & 0x7f
    masked = bool(header[1] & 0x80)

    if payload_len == 126:
        payload_len = int.from_bytes(recv_exact(sock, 2), "big")
    elif payload_len == 127:
        payload_len = int.from_bytes(recv_exact(sock, 8), "big")

    mask = recv_exact(sock, 4) if masked else None
    data = bytearray(recv_exact(sock, payload_len))
    if mask:
        for i in range(len(data)):
            data[i] ^= mask[i % 4]
    return bytes(data)


def send_binary_frame(sock, payload):
    mask_key = os.urandom(4)
    frame = bytearray([0x82])
    if len(payload) < 126:
        frame.append(0x80 | len(payload))
    elif len(payload) <= 0xffff:
        frame.append(0x80 | 126)
        frame.extend(len(payload).to_bytes(2, "big"))
    else:
        frame.append(0x80 | 127)
        frame.extend(len(payload).to_bytes(8, "big"))
    frame.extend(mask_key)
    frame.extend(byte ^ mask_key[i % 4] for i, byte in enumerate(payload))
    sock.sendall(frame)


def test_nginx_running():
    """Test that Nginx is running and listening on port 8080."""
    try:
        output = subprocess.check_output(["pgrep", "-f", "nginx"], text=True)
        assert output.strip() != "", "Nginx is not running."
    except subprocess.CalledProcessError:
        pytest.fail("Nginx is not running.")


def test_server_running_under_valgrind():
    """Test that divn_server is running under valgrind."""
    try:
        output = subprocess.check_output(["pgrep", "-f", "valgrind.*divn_server"], text=True)
        assert output.strip() != "", "divn_server is not running under valgrind."
    except subprocess.CalledProcessError:
        pytest.fail("divn_server is not running under valgrind.")


def test_websocket_fletcher16_and_memory_leak():
    """Test the websocket proxy, standard Fletcher-16 calculation, and memory leak fix."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(("127.0.0.1", 8080))
    except Exception as e:
        pytest.fail(f"Could not connect to Nginx on port 8080: {e}")

    key = base64.b64encode(os.urandom(16)).decode("utf-8")
    req = (
        "GET / HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s.sendall(req.encode())

    try:
        handshake_resp = s.recv(4096)
        assert b"101 Switching Protocols" in handshake_resp, \
            "WebSocket handshake failed. Is Nginx proxying headers correctly?"
    except Exception as e:
        pytest.fail(f"Failed to receive handshake response: {e}")

    # Include the original regression payload and unpredictable binary inputs so
    # the expected values come from the requested standard algorithm.
    payloads = [
        b"hello world",
        bytes(range(32)),
        os.urandom(37),
    ]

    try:
        for payload in payloads:
            send_binary_frame(s, payload)
            data = recv_websocket_payload(s)
            expected = fletcher16(payload)
            expected_decimal = str(expected)
            expected_hex = f"{expected:04x}"
            resp_str = data.decode("utf-8", errors="ignore").lower()
            resp_hex = data.hex().lower()
            assert expected_decimal in resp_str or expected_hex in resp_str or expected_hex in resp_hex, \
                f"Fletcher-16 checksum incorrect. Expected {expected_decimal} (0x{expected_hex}), got: {data!r}"
    except Exception as e:
        if isinstance(e, AssertionError):
            raise
        pytest.fail(f"Failed while exchanging WebSocket frames: {e}")
    finally:
        s.close()

    subprocess.run(["pkill", "-INT", "-f", "divn_server"])

    for _ in range(10):
        time.sleep(0.5)
        if subprocess.run(["pgrep", "-f", "valgrind.*divn_server"]).returncode != 0:
            break

    valgrind_log_path = "/home/user/valgrind.log"
    assert os.path.exists(valgrind_log_path), f"{valgrind_log_path} does not exist."

    with open(valgrind_log_path, "r") as f:
        log_content = f.read()

    leak_free = "definitely lost: 0 bytes in 0 blocks" in log_content or \
                "All heap blocks were freed -- no leaks are possible" in log_content

    assert leak_free, "Memory leak detected in valgrind.log. Ensure you freed the allocated buffer."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
