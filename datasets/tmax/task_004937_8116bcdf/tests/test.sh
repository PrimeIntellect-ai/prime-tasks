#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import binascii
import hashlib
import os
import random
import secrets
import signal
import stat
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

ORACLE_PATH = '/app/oracle_decoder'
assert os.path.isfile(ORACLE_PATH), f"Oracle {ORACLE_PATH} is missing."
assert os.access(ORACLE_PATH, os.X_OK), f"Oracle {ORACLE_PATH} is not executable."

# Retain the oracle only in verifier memory while testing. This prevents a
# submitted wrapper from delegating decoding back to /app/oracle_decoder.
with open(ORACLE_PATH, 'rb') as f:
    ORACLE_BYTES = f.read()
ORACLE_MODE = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)
ORACLE_HASH = hashlib.sha256(ORACLE_BYTES).digest()
os.unlink(ORACLE_PATH)


def restore_oracle():
    try:
        with open(ORACLE_PATH, 'wb') as f:
            f.write(ORACLE_BYTES)
        os.chmod(ORACLE_PATH, ORACLE_MODE)
    except Exception:
        pass


atexit.register(restore_oracle)


def listening_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if int(local.rsplit(':', 1)[1], 16) == port and state == '0A':
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_backend(port=8081):
    pids = listening_pids(port)
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids(port):
        time.sleep(0.05)
    for pid in listening_pids(port):
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 2
    while time.time() < deadline and listening_pids(port):
        time.sleep(0.05)
    assert not listening_pids(port), f"Could not free backend port {port}"


def test_nginx_routing():
    """Test both the original ping and actual prefix-stripping proxy behavior."""
    url = 'http://localhost:8080/api/v1/ping'
    try:
        with urllib.request.urlopen(url, timeout=2) as response:
            status_code = response.getcode()
            body = response.read().decode('utf-8').strip()
            assert status_code == 200, f"Expected HTTP 200, got {status_code}"
            assert body == 'pong', f"Expected response body 'pong', got {body!r}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect or retrieve data from {url}: {e}")

    # Replace the backend with a verifier-controlled server. A fresh random
    # endpoint and response prove that Nginx proxies rather than returning a
    # hard-coded pong, and the recorded path proves the prefix was stripped.
    stop_backend()
    endpoint = 'audit-' + secrets.token_hex(12)
    query = 'probe=' + secrets.token_hex(8)
    expected_path = f'/{endpoint}?{query}'
    response_token = ('proxied-' + secrets.token_hex(24)).encode()
    seen = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            seen.append(self.path)
            self.send_response(200)
            self.send_header('Content-Length', str(len(response_token)))
            self.end_headers()
            self.wfile.write(response_token)

        def log_message(self, fmt, *args):
            pass

    server = HTTPServer(('127.0.0.1', 8081), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        dynamic_url = f'http://localhost:8080/api/v1/{endpoint}?{query}'
        with urllib.request.urlopen(dynamic_url, timeout=2) as response:
            assert response.getcode() == 200
            assert response.read() == response_token
        assert seen == [expected_path], (
            f"Backend should receive {expected_path!r} after prefix stripping; got {seen!r}"
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        subprocess.Popen(
            ['python3', '/app/go_api.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )


def test_decoder_exists_and_executable():
    """Ensure the user's decoder is a real executable file."""
    decoder_path = '/home/user/decoder'
    assert os.path.isfile(decoder_path), f"Decoder script {decoder_path} is missing."
    assert not os.path.islink(decoder_path), f"Decoder {decoder_path} must not be a symlink."
    assert stat.S_ISREG(os.stat(decoder_path).st_mode), f"Decoder {decoder_path} is not a regular file."
    assert os.access(decoder_path, os.X_OK), f"Decoder script {decoder_path} is not executable."
    with open(decoder_path, 'rb') as f:
        assert hashlib.sha256(f.read()).digest() != ORACLE_HASH, (
            'Decoder must not be a byte-for-byte copy of the oracle.'
        )


def expected_decode(hex_input):
    data = binascii.unhexlify(hex_input)
    return bytes((byte ^ 0x5A) for byte in reversed(data))


def test_decoder_fuzz_equivalence():
    """Exercise the decoder against independently derived expected outputs."""
    agent_path = '/home/user/decoder'
    random.seed(42)

    for _ in range(100):
        length = random.randint(0, 256)
        random_bytes = bytearray(random.getrandbits(8) for _ in range(length))
        hex_input = binascii.hexlify(random_bytes).decode('ascii')
        expected = expected_decode(hex_input)

        assert not os.path.exists(ORACLE_PATH), 'Oracle unexpectedly became available during testing.'
        agent_proc = subprocess.run([agent_path, hex_input], capture_output=True)
        assert not os.path.exists(ORACLE_PATH), 'Decoder recreated or exposed the oracle path.'

        assert agent_proc.stdout == expected, (
            f"Output mismatch on input {hex_input!r} (length {length}).\n"
            f"Expected stdout: {expected!r}\n"
            f"Agent stdout: {agent_proc.stdout!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
