#!/bin/bash
set +e
mkdir -p /logs/verifier
rm -f /tmp/cargo_build_ok /tmp/telemetry-proxy.pid

# Build the submitted Rust project, then execute that exact artifact for testing.
if cargo build --manifest-path /app/rust-proxy/Cargo.toml; then
    touch /tmp/cargo_build_ok

    python3 - <<'PY'
import os
import signal
import time

port_hex = format(8080, '04X')
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                cols = line.split()
                if len(cols) >= 10 and cols[1].split(':')[-1].upper() == port_hex and cols[3] == '0A':
                    inodes.add(cols[9])
    except OSError:
        pass

for pid in os.listdir('/proc'):
    if not pid.isdigit():
        continue
    fd_dir = f'/proc/{pid}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(pid), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass

time.sleep(1)
PY

    cd /app/rust-proxy
    nohup /app/rust-proxy/target/debug/telemetry-proxy >/tmp/verifier-proxy.log 2>&1 &
    echo $! > /tmp/telemetry-proxy.pid
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import copy
import importlib.util
import json
import os
import random
import socket
import time
import uuid

import pytest
import redis

CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
PROXY_BINARY = os.path.realpath("/app/rust-proxy/target/debug/telemetry-proxy")


def send_ws_message(port, message):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect(('localhost', port))
        key = base64.b64encode(os.urandom(16)).decode('utf-8')
        request = (
            f"GET / HTTP/1.1\r\n"
            f"Host: localhost:{port}\r\n"
            f"Upgrade: websocket\r\n"
            f"Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            f"Sec-WebSocket-Version: 13\r\n\r\n"
        )
        s.sendall(request.encode())
        resp = s.recv(4096)
        if b"101 Switching Protocols" not in resp:
            raise Exception("WebSocket handshake failed")

        msg_bytes = message.encode('utf-8')
        length = len(msg_bytes)
        frame = bytearray([0x81])
        if length < 126:
            frame.append(length | 0x80)
        elif length < 65536:
            frame.append(126 | 0x80)
            frame.extend(length.to_bytes(2, 'big'))
        else:
            frame.append(127 | 0x80)
            frame.extend(length.to_bytes(8, 'big'))
        mask = os.urandom(4)
        frame.extend(mask)
        frame.extend(msg_bytes[i] ^ mask[i % 4] for i in range(length))
        s.sendall(frame)
    finally:
        s.close()


def redis_command(cmd_args):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect(('localhost', 6379))
        parts = [f"*{len(cmd_args)}\r\n".encode()]
        for arg in cmd_args:
            arg_bytes = str(arg).encode('utf-8')
            parts.append(f"${len(arg_bytes)}\r\n".encode())
            parts.append(arg_bytes + b"\r\n")
        s.sendall(b''.join(parts))
        return s.recv(8192)
    finally:
        s.close()


def listener_pids(port):
    port_hex = format(port, '04X')
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    cols = line.split()
                    if len(cols) >= 10 and cols[1].split(':')[-1].upper() == port_hex and cols[3] == '0A':
                        inodes.add(cols[9])
        except OSError:
            pass

    result = set()
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        try:
            for fd in os.listdir(f'/proc/{pid}/fd'):
                try:
                    target = os.readlink(f'/proc/{pid}/fd/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(pid))
                    break
        except OSError:
            pass
    return result


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('localhost', port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Service did not start on port {port}")


def load_corpus(path):
    files = sorted(f for f in os.listdir(path) if f.endswith('.json'))
    return [(name, open(os.path.join(path, name), 'r').read()) for name in files]


def assert_exact_redis(expected):
    client = redis.Redis(host='localhost', port=6379, db=0)
    actual_keys = set(client.keys('*'))
    expected_keys = {str(key).encode() for key in expected}
    assert client.dbsize() == len(expected), (
        f"Expected {len(expected)} clean entries in Redis, but found {client.dbsize()}. "
        "This means either clean payloads were dropped or evil payloads were accepted."
    )
    assert actual_keys == expected_keys, f"Unexpected Redis keys: {actual_keys ^ expected_keys}"
    for key, expected_value in expected.items():
        raw = client.get(str(key))
        assert raw is not None, f"Missing clean payload with id {key}"
        assert json.loads(raw) == expected_value, f"Incorrect stored value for id {key}"


def test_environment_ready():
    assert os.path.exists("/home/user/environment_ready.log"), "The /home/user/environment_ready.log file is missing."
    with open("/home/user/environment_ready.log", "r") as f:
        assert "READY" in f.read(), "The environment_ready.log does not contain 'READY'."


def test_services_running_and_compiled_proxy_executed():
    assert os.path.exists('/tmp/cargo_build_ok'), "The Rust project did not compile with cargo build."
    assert os.path.isfile(PROXY_BINARY) and os.access(PROXY_BINARY, os.X_OK), "Compiled Rust proxy is missing."

    try:
        resp = redis_command(["PING"])
        assert b"PONG" in resp, "Redis is not responding properly."
    except Exception as e:
        pytest.fail(f"Redis is not running on port 6379: {e}")

    for port, name in ((5000, 'Python backend'), (8080, 'Rust Proxy')):
        try:
            with socket.create_connection(('localhost', port), timeout=2):
                pass
        except Exception as e:
            pytest.fail(f"{name} is not running on port {port}: {e}")

    pids = listener_pids(8080)
    assert pids, "No process is listening on port 8080."
    executables = set()
    for pid in pids:
        try:
            executables.add(os.path.realpath(f'/proc/{pid}/exe'))
        except OSError:
            pass
    assert PROXY_BINARY in executables, f"Port 8080 is not served by the compiled Rust artifact: {executables}"


def test_adversarial_corpus():
    client = redis.Redis(host='localhost', port=6379, db=0)
    client.flushall()

    clean_files = load_corpus(CLEAN_DIR)
    evil_files = load_corpus(EVIL_DIR)
    assert len(clean_files) > 0, "No clean payloads found."
    assert len(evil_files) > 0, "No evil payloads found."

    expected = {}
    messages = []
    for name, payload in clean_files:
        obj = json.loads(payload)
        assert isinstance(obj, dict) and 'id' in obj, f"Invalid clean fixture {name}"
        expected[str(obj['id'])] = obj
        messages.append(payload)
    messages.extend(payload for _, payload in evil_files)

    random.SystemRandom().shuffle(messages)
    for payload in messages:
        send_ws_message(8080, payload)

    time.sleep(2)
    assert_exact_redis(expected)


def test_generated_validation_cases():
    client = redis.Redis(host='localhost', port=6379, db=0)
    client.flushall()

    spec = importlib.util.spec_from_file_location('checksum_reference', '/app/reference/checksum.py')
    checksum_reference = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checksum_reference)

    clean_files = load_corpus(CLEAN_DIR)
    expected = {}
    messages = []
    for _, payload in clean_files:
        obj = copy.deepcopy(json.loads(payload))
        obj['id'] = 'generated-' + uuid.uuid4().hex
        if isinstance(obj.get('data'), str):
            obj['data'] = 'probe-' + uuid.uuid4().hex
        assert checksum_reference.validate_checksum(obj) is True
        expected[obj['id']] = obj
        messages.append(json.dumps(obj))

    nonce = uuid.uuid4().hex
    malformed = [
        '{',
        '["' + nonce + '"]',
        json.dumps("not-an-object-" + nonce),
        json.dumps({'data': 'missing-id-' + nonce}),
        json.dumps({'id': None, 'data': 'null-id-' + nonce}),
    ]
    messages.extend(malformed)
    random.SystemRandom().shuffle(messages)
    for payload in messages:
        send_ws_message(8080, payload)

    time.sleep(2)
    assert_exact_redis(expected)
TEST_EOF

wait_status=0
python3 - <<'PY' || wait_status=1
import socket, time, sys
deadline = time.time() + 10
while time.time() < deadline:
    try:
        with socket.create_connection(('localhost', 8080), timeout=.25):
            sys.exit(0)
    except OSError:
        time.sleep(.1)
sys.exit(1)
PY

if [ "$wait_status" -eq 0 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
