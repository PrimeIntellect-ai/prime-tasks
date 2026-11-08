#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import secrets
import signal
import socket
import subprocess
import time
import zlib

import pytest

PYTHON_PATH = '/home/user/venv/bin/python'
DATA_PATH = '/home/user/data.json'
PROCESSOR_PATH = '/home/user/ws_processor.py'
LOG_PATH = '/home/user/success.log'


def test_venv_exists():
    """Test that the virtual environment was created."""
    assert os.path.exists(PYTHON_PATH), f"Virtual environment Python executable not found at {PYTHON_PATH}."


def test_websockets_installed():
    """Test that the websockets package is installed in the virtual environment."""
    if not os.path.exists(PYTHON_PATH):
        pytest.fail("Virtual environment not found, cannot check for websockets.")

    result = subprocess.run([PYTHON_PATH, '-c', 'import websockets'], capture_output=True)
    assert result.returncode == 0, "The 'websockets' package is not installed in the virtual environment."


def test_success_log_content():
    """Test that success.log exists and contains the correct payload and checksum."""
    assert os.path.exists(LOG_PATH), f"{LOG_PATH} is missing. The script may not have run successfully."
    assert os.path.exists(DATA_PATH), f"{DATA_PATH} is missing."

    with open(DATA_PATH, 'r') as f:
        data = json.load(f)

    expected_payload = json.dumps(data, sort_keys=True)
    expected_checksum = zlib.crc32(expected_payload.encode('utf-8'))

    with open(LOG_PATH, 'r') as f:
        log_content = f.read()

    try:
        log_data = json.loads(log_content)
    except json.JSONDecodeError:
        pytest.fail(f"{LOG_PATH} does not contain valid JSON.")

    assert "payload" in log_data, f"'payload' key missing in {LOG_PATH}."
    assert "checksum" in log_data, f"'checksum' key missing in {LOG_PATH}."
    assert log_data["payload"] == expected_payload, f"Expected payload '{expected_payload}', but got '{log_data['payload']}'."
    assert log_data["checksum"] == expected_checksum, f"Expected checksum {expected_checksum}, but got {log_data['checksum']}."


def _echo_server_pids():
    pids = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                argv = [x.decode(errors='replace') for x in f.read().split(b'\0') if x]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if '/home/user/echo_server.py' in argv and any(arg.startswith('/home/user/venv/bin/python') for arg in argv):
            pids.append(int(entry))
    return pids


def test_processor_executes_over_websocket_on_fresh_input(tmp_path):
    """Require the agent's server and execute the processor against an observed WebSocket exchange."""
    assert os.path.isfile(PROCESSOR_PATH), f"{PROCESSOR_PATH} is missing or is not a regular file."

    server_pids = _echo_server_pids()
    assert server_pids, "The provided echo_server.py was not left running with the virtual environment."

    nonce = secrets.token_hex(16)
    probe = subprocess.run(
        [PYTHON_PATH, '-c',
         'import asyncio,sys,websockets\n'
         'async def main():\n'
         '    async with websockets.connect("ws://localhost:8765") as ws:\n'
         '        await ws.send(sys.argv[1])\n'
         '        assert await ws.recv() == sys.argv[1]\n'
         'asyncio.run(main())', nonce],
        capture_output=True, text=True, timeout=10)
    assert probe.returncode == 0, f"The running echo server did not echo a WebSocket probe: {probe.stderr}"

    original_data = open(DATA_PATH, 'rb').read()
    original_log = open(LOG_PATH, 'rb').read() if os.path.exists(LOG_PATH) else None
    capture_path = str(tmp_path / 'captured-message.bin')
    ready_path = str(tmp_path / 'server-ready')

    raw_server = r'''
import base64, hashlib, os, socket, struct, sys
capture, ready = sys.argv[1], sys.argv[2]

def recvn(conn, count):
    out = b''
    while len(out) < count:
        part = conn.recv(count - len(out))
        if not part:
            raise RuntimeError('unexpected EOF')
        out += part
    return out

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', 8765))
    listener.listen(1)
    open(ready, 'w').close()
    conn, _ = listener.accept()
    with conn:
        request = b''
        while b'\r\n\r\n' not in request:
            request += conn.recv(4096)
        headers = {}
        for line in request.decode('latin1').split('\r\n')[1:]:
            if ':' in line:
                key, value = line.split(':', 1)
                headers[key.strip().lower()] = value.strip()
        accept = base64.b64encode(hashlib.sha1((headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        conn.sendall(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n').encode())
        first, second = recvn(conn, 2)
        assert (first & 0x0f) == 1
        length = second & 0x7f
        if length == 126:
            length = struct.unpack('!H', recvn(conn, 2))[0]
        elif length == 127:
            length = struct.unpack('!Q', recvn(conn, 8))[0]
        mask = recvn(conn, 4) if second & 0x80 else b''
        payload = recvn(conn, length)
        if mask:
            payload = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
        with open(capture, 'wb') as f:
            f.write(payload)
        if len(payload) < 126:
            header = bytes([0x81, len(payload)])
        elif len(payload) <= 65535:
            header = bytes([0x81, 126]) + struct.pack('!H', len(payload))
        else:
            header = bytes([0x81, 127]) + struct.pack('!Q', len(payload))
        conn.sendall(header + payload)
'''

    controlled = None
    try:
        for pid in server_pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        deadline = time.time() + 5
        while time.time() < deadline and any(os.path.exists(f'/proc/{pid}') for pid in server_pids):
            time.sleep(0.05)
        for pid in server_pids:
            if os.path.exists(f'/proc/{pid}'):
                os.kill(pid, signal.SIGKILL)

        challenge = {
            'id': secrets.randbelow(1_000_000),
            'event': 'verifier_' + secrets.token_hex(12),
            'nested': {'value': secrets.token_hex(8)}
        }
        with open(DATA_PATH, 'w') as f:
            json.dump(challenge, f)

        controlled = subprocess.Popen(
            [PYTHON_PATH, '-c', raw_server, capture_path, ready_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        deadline = time.time() + 5
        while not os.path.exists(ready_path) and controlled.poll() is None and time.time() < deadline:
            time.sleep(0.05)
        assert os.path.exists(ready_path), f"Controlled WebSocket server failed to start: {controlled.stderr.read()}"

        if os.path.exists(LOG_PATH):
            os.unlink(LOG_PATH)
        run = subprocess.run([PYTHON_PATH, PROCESSOR_PATH], capture_output=True, text=True, timeout=15)
        assert run.returncode == 0, f"ws_processor.py failed when executed: {run.stderr}"
        controlled.wait(timeout=5)
        assert controlled.returncode == 0, f"WebSocket observer failed: {controlled.stderr.read()}"
        assert os.path.exists(capture_path), "ws_processor.py did not send a WebSocket message."
        assert os.path.exists(LOG_PATH), "ws_processor.py did not create success.log after receiving the echo."

        expected_payload = json.dumps(challenge, sort_keys=True)
        expected_checksum = zlib.crc32(expected_payload.encode('utf-8'))
        sent = json.loads(open(capture_path, 'rb').read().decode('utf-8'))
        logged = json.loads(open(LOG_PATH, 'r').read())
        assert sent['payload'] == expected_payload
        assert sent['checksum'] == expected_checksum
        assert logged == sent, "success.log was not the response echoed by the WebSocket server."
    finally:
        if controlled is not None and controlled.poll() is None:
            controlled.kill()
            controlled.wait()
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        if original_log is None:
            if os.path.exists(LOG_PATH):
                os.unlink(LOG_PATH)
        else:
            with open(LOG_PATH, 'wb') as f:
                f.write(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
