#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import re
import socket
import subprocess
import tempfile
import threading
import time
import uuid


def recv_exact(s, n):
    data = b''
    while len(data) < n:
        chunk = s.recv(n - len(data))
        if not chunk:
            raise ConnectionError('unexpected EOF')
        data += chunk
    return data


def ws_connect(host, port, path, headers=None):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    s.connect((host, port))
    key = base64.b64encode(os.urandom(16)).decode('utf-8')
    req = f'GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n'
    if headers:
        for k, v in headers.items():
            req += f'{k}: {v}\r\n'
    req += '\r\n'
    s.sendall(req.encode('utf-8'))
    resp = s.recv(4096)
    return s, resp


def ws_send_text(s, text):
    payload = text.encode('utf-8')
    header = bytearray([0x81])
    mask_key = os.urandom(4)
    length = len(payload)
    if length < 126:
        header.append(length | 0x80)
    elif length < 65536:
        header.append(126 | 0x80)
        header.extend(length.to_bytes(2, 'big'))
    else:
        header.append(127 | 0x80)
        header.extend(length.to_bytes(8, 'big'))
    header.extend(mask_key)
    header.extend(bytes(payload[i] ^ mask_key[i % 4] for i in range(length)))
    s.sendall(header)


def ws_recv_text(s):
    while True:
        b1, b2 = recv_exact(s, 2)
        opcode = b1 & 0x0f
        length = b2 & 0x7f
        if length == 126:
            length = int.from_bytes(recv_exact(s, 2), 'big')
        elif length == 127:
            length = int.from_bytes(recv_exact(s, 8), 'big')
        mask = recv_exact(s, 4) if b2 & 0x80 else None
        payload = recv_exact(s, length)
        if mask:
            payload = bytes(payload[i] ^ mask[i % 4] for i in range(length))
        if opcode == 1:
            return payload.decode('utf-8')
        if opcode == 8:
            return None


def test_websocket_server_unauthorized():
    s, resp = ws_connect('127.0.0.1', 8080, '/ws/device_99')
    s.close()
    resp_str = resp.decode('utf-8', errors='ignore')
    assert '401' in resp_str.split('\r\n')[0], f'Expected HTTP 401 Unauthorized, got: {resp_str}'


def test_websocket_server_authorized_and_payloads():
    headers = {'Authorization': 'Bearer TKN_A93F8B2C'}
    s, resp = ws_connect('127.0.0.1', 8080, '/ws/device_99', headers)
    resp_str = resp.decode('utf-8', errors='ignore')
    assert '101' in resp_str.split('\r\n')[0], f'Expected HTTP 101 Switching Protocols, got: {resp_str}'

    payload1 = {'id': 'test_1', 'hex_code': '48c7c00100000048c7c302000000'}
    ws_send_text(s, json.dumps(payload1))
    resp1_text = ws_recv_text(s)
    assert resp1_text is not None, 'Did not receive response for test_1'
    resp1 = json.loads(resp1_text)
    assert resp1.get('id') == 'test_1', f"Expected id 'test_1', got {resp1.get('id')}"
    assert resp1.get('mov_count') == 2, f"Expected mov_count 2, got {resp1.get('mov_count')}"

    payload2 = {'id': 'test_2', 'hex_code': '909090'}
    ws_send_text(s, json.dumps(payload2))
    resp2_text = ws_recv_text(s)
    assert resp2_text is not None, 'Did not receive response for test_2'
    resp2 = json.loads(resp2_text)
    assert resp2.get('id') == 'test_2', f"Expected id 'test_2', got {resp2.get('id')}"
    assert resp2.get('mov_count') == 0, f"Expected mov_count 0, got {resp2.get('mov_count')}"
    s.close()


def test_telemetry_log_contents():
    time.sleep(1)
    log_path = '/app/telemetry.log'
    assert os.path.exists(log_path), f'Log file {log_path} does not exist.'
    with open(log_path) as f:
        lines = [line.strip() for line in f if line.strip()]
    found_test_1 = False
    found_test_2 = False
    for line in lines:
        try:
            entry = json.loads(line)
            if entry.get('device_id') == 'device_99' and entry.get('msg_id') == 'test_1' and entry.get('mov_count') == 2:
                found_test_1 = True
            if entry.get('device_id') == 'device_99' and entry.get('msg_id') == 'test_2' and entry.get('mov_count') == 0:
                found_test_2 = True
        except json.JSONDecodeError:
            continue
    assert found_test_1, 'Log entry for test_1 not found or incorrect in /app/telemetry.log'
    assert found_test_2, 'Log entry for test_2 not found or incorrect in /app/telemetry.log'


def test_binding_and_additional_routing_authentication():
    listeners = []
    for procfile in ('/proc/net/tcp', '/proc/net/tcp6'):
        with open(procfile) as f:
            next(f)
            for line in f:
                fields = line.split()
                addr, port = fields[1].split(':')
                if int(port, 16) == 8080 and fields[3] == '0A':
                    listeners.append((procfile, addr))
    assert listeners, 'No listener found on port 8080'
    assert all(p == '/proc/net/tcp' and a == '0100007F' for p, a in listeners), f'Server is not bound strictly to 127.0.0.1:8080: {listeners}'

    bad = 'Bearer BAD_' + uuid.uuid4().hex
    s, resp = ws_connect('127.0.0.1', 8080, '/ws/' + uuid.uuid4().hex, {'Authorization': bad})
    s.close()
    assert '401' in resp.decode('utf-8', errors='ignore').split('\r\n')[0]

    s, resp = ws_connect('127.0.0.1', 8080, '/not-ws/' + uuid.uuid4().hex, {'Authorization': 'Bearer TKN_A93F8B2C'})
    s.close()
    assert '101' not in resp.decode('utf-8', errors='ignore').split('\r\n')[0], 'Non-/ws route upgraded unexpectedly'


def objdump_mov_count(code):
    with tempfile.NamedTemporaryFile() as f:
        f.write(code)
        f.flush()
        output = subprocess.check_output([
            'objdump', '-D', '-b', 'binary', '-m', 'i386:x86-64',
            '--insn-width=16', f.name
        ], text=True)
    count = 0
    for line in output.splitlines():
        match = re.match(r'^\s*[0-9a-f]+:\s+(?:[0-9a-f]{2}\s+)+\s*([a-z][a-z0-9]*)', line)
        if match and match.group(1).startswith('mov'):
            count += 1
    return count


def random_snippet():
    movs = [
        lambda: b'\x48\xc7\xc0' + os.urandom(4),
        lambda: b'\x48\xb8' + os.urandom(8),
        lambda: b'\x89\xd8',
        lambda: b'\x48\x89\xd8',
        lambda: b'\xb9' + os.urandom(4),
        lambda: b'\x8a\x03',
    ]
    others = [b'\x90', b'\x31\xc0', b'\x48\x01\xd8', b'\x48\x8d\x04\x33', b'\x50', b'\x58', b'\x0f\xaf\xc3']
    wanted = random.randint(1, 6)
    pieces = [random.choice(movs)() for _ in range(wanted)]
    pieces += [random.choice(others) for _ in range(random.randint(1, 7))]
    random.shuffle(pieces)
    code = b''.join(pieces)
    expected = objdump_mov_count(code)
    assert expected == wanted, 'Verifier disassembly sanity check failed'
    return code.hex(), expected


def test_randomized_decoding_concurrency_and_append_only_logging():
    log_path = '/app/telemetry.log'
    with open(log_path, 'rb') as f:
        old_log = f.read()

    worker_count = 5
    per_worker = 4
    barrier = threading.Barrier(worker_count)
    expected_entries = []
    errors = []
    guard = threading.Lock()

    jobs = []
    for _ in range(worker_count):
        device = 'dev_' + uuid.uuid4().hex
        messages = []
        for _ in range(per_worker):
            msg_id = 'msg_' + uuid.uuid4().hex
            hex_code, count = random_snippet()
            messages.append((msg_id, hex_code, count))
            expected_entries.append({'device_id': device, 'msg_id': msg_id, 'mov_count': count})
        jobs.append((device, messages))

    def worker(device, messages):
        s = None
        try:
            s, handshake = ws_connect('127.0.0.1', 8080, '/ws/' + device, {'Authorization': 'Bearer TKN_A93F8B2C'})
            assert '101' in handshake.decode('utf-8', errors='ignore').split('\r\n')[0]
            barrier.wait(timeout=5)
            for msg_id, hex_code, count in messages:
                ws_send_text(s, json.dumps({'id': msg_id, 'hex_code': hex_code}))
                response = json.loads(ws_recv_text(s))
                assert response.get('id') == msg_id
                assert response.get('mov_count') == count, (hex_code, count, response)
        except BaseException as exc:
            with guard:
                errors.append(repr(exc))
        finally:
            if s:
                s.close()

    threads = [threading.Thread(target=worker, args=job) for job in jobs]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(15)
    assert not any(thread.is_alive() for thread in threads), 'Concurrent WebSocket workers hung'
    assert not errors, '; '.join(errors)

    deadline = time.time() + 5
    missing = expected_entries
    while time.time() < deadline:
        with open(log_path, 'rb') as f:
            current = f.read()
        assert current.startswith(old_log), 'Telemetry log was truncated or rewritten instead of appended'
        parsed = []
        malformed = []
        for raw in current.splitlines():
            if not raw.strip():
                continue
            try:
                parsed.append(json.loads(raw))
            except Exception:
                malformed.append(raw)
        assert not malformed, 'Telemetry log contains non-JSON lines'
        missing = [entry for entry in expected_entries if entry not in parsed]
        if not missing:
            break
        time.sleep(0.1)
    assert not missing, f'Missing randomized concurrent log entries: {missing}'

    for entry in expected_entries:
        assert set(entry) == {'device_id', 'msg_id', 'mov_count'}
        assert isinstance(entry['mov_count'], int)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
