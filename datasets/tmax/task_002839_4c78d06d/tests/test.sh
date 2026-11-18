#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import secrets
import socket
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/build_proxy')
ANALYZER = Path('/app/build_analyzer')


def recv_until_headers(s):
    data = b''
    while b'\r\n\r\n' not in data and len(data) < 65536:
        try:
            chunk = s.recv(4096)
        except ConnectionResetError:
            break
        if not chunk:
            break
        data += chunk
    return data


def handshake(host, port, path):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((host, port))
    key = base64.b64encode(os.urandom(16)).decode('ascii')
    req = (
        f'GET {path} HTTP/1.1\r\n'
        f'Host: {host}:{port}\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        f'Sec-WebSocket-Key: {key}\r\n'
        'Sec-WebSocket-Version: 13\r\n\r\n'
    )
    s.sendall(req.encode('ascii'))
    return s, recv_until_headers(s)


def ws_connect(host, port, path):
    try:
        s, resp = handshake(host, port, path)
    except Exception as e:
        pytest.fail(f'Failed to connect to {host}:{port}: {e}')
    if b'101 Switching Protocols' not in resp:
        s.close()
        pytest.fail(f'WebSocket handshake failed. Response: {resp}')
    return s


def recv_exact(s, count):
    data = b''
    while len(data) < count:
        chunk = s.recv(count - len(data))
        if not chunk:
            raise AssertionError('WebSocket connection closed mid-frame')
        data += chunk
    return data


def ws_send(s, text):
    msg = text.encode('utf-8')
    if len(msg) > 125:
        pytest.fail('Test message too long for simple WS client')
    mask_key = os.urandom(4)
    header = bytearray([0x81, 0x80 | len(msg)])
    header.extend(mask_key)
    masked = bytearray(msg[i] ^ mask_key[i % 4] for i in range(len(msg)))
    s.sendall(header + masked)


def ws_recv(s):
    while True:
        header = recv_exact(s, 2)
        opcode = header[0] & 0x0f
        length = header[1] & 0x7f
        if length == 126:
            length = int.from_bytes(recv_exact(s, 2), 'big')
        elif length == 127:
            length = int.from_bytes(recv_exact(s, 8), 'big')
        if header[1] & 0x80:
            mask = recv_exact(s, 4)
        else:
            mask = None
        data = recv_exact(s, length)
        if mask:
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        if opcode == 0x8:
            return None
        if opcode == 0x9:
            continue
        if opcode in (0x1, 0x0):
            return data.decode('utf-8')


def release_binaries():
    assert PROJECT.is_dir(), 'Missing /home/user/build_proxy project directory'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Missing Cargo.toml'
    assert (PROJECT / 'src' / 'main.rs').is_file(), 'Missing src/main.rs'
    assert (PROJECT / 'src' / 'main.rs').stat().st_size > 0, 'src/main.rs is empty'

    result = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1',
         '--manifest-path', str(PROJECT / 'Cargo.toml')],
        text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, f'Invalid Rust project: {result.stderr}'
    metadata = json.loads(result.stdout)
    root_manifest = str((PROJECT / 'Cargo.toml').resolve())
    packages = [p for p in metadata['packages']
                if str(Path(p['manifest_path']).resolve()) == root_manifest]
    assert packages, 'Cargo metadata does not describe the requested project'

    target_dir = Path(metadata['target_directory']) / 'release'
    bins = []
    for package in packages:
        for target in package.get('targets', []):
            if 'bin' in target.get('kind', []):
                candidate = target_dir / target['name']
                if candidate.is_file() and os.access(candidate, os.X_OK):
                    with candidate.open('rb') as f:
                        assert f.read(4) == b'\x7fELF', f'{candidate} is not a compiled executable'
                    bins.append(candidate.resolve())
    assert bins, 'No compiled release-mode Rust binary was found'
    return bins


def listener_pids(port):
    socket_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                socket_inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                if link.startswith('socket:[') and link[8:-1] in socket_inodes:
                    pids.add(int(proc.name))
        except OSError:
            continue
    return pids


def assert_release_binary_is_listening(binaries):
    pids = listener_pids(9050)
    assert pids, 'No process is listening on port 9050'
    listener_exes = []
    for pid in pids:
        try:
            listener_exes.append(Path(os.readlink(f'/proc/{pid}/exe')).resolve())
        except OSError:
            pass
    assert any(any(os.path.samefile(exe, binary) for binary in binaries)
               for exe in listener_exes for binary in binaries), \
        f'Port 9050 is not served by a compiled release binary: {listener_exes}'


def install_probe_analyzer():
    token = secrets.token_hex(16)
    prefix = f'build_proxy_probe_{token}_'
    log_path = Path(f'/tmp/{prefix}calls.jsonl')
    backup = Path(f'/app/build_analyzer.original.{token}')
    os.replace(ANALYZER, backup)
    script = f'''#!/usr/bin/env python3
import hashlib, json, os, subprocess, sys
args = sys.argv[1:]
probe = len(args) == 1 and os.path.basename(args[0]).startswith({prefix!r})
if probe:
    with open({str(log_path)!r}, 'a') as log:
        log.write(json.dumps(args) + "\\n")
result = subprocess.run([{str(backup)!r}] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
sys.stdout.buffer.write(result.stdout)
if probe and result.returncode == 0:
    data = open(args[0], 'rb').read()
    marker = 'PROBE:{token}:' + hashlib.sha256(data).hexdigest() + ':' + str(len(data)) + '\\n'
    sys.stdout.write(marker)
sys.exit(result.returncode)
'''
    ANALYZER.write_text(script)
    ANALYZER.chmod(0o755)
    return token, prefix, log_path, backup


def restore_analyzer(backup):
    try:
        ANALYZER.unlink(missing_ok=True)
    finally:
        if backup.exists():
            os.replace(backup, ANALYZER)


def test_websocket_server():
    binaries = release_binaries()
    assert_release_binary_is_listening(binaries)

    # The WebSocket upgrade must be restricted to the requested endpoint.
    wrong, wrong_resp = handshake('127.0.0.1', 9050, '/not-analyze')
    wrong.close()
    assert b'101 Switching Protocols' not in wrong_resp, \
        'Server accepted a WebSocket connection on the wrong endpoint'

    token, prefix, log_path, backup = install_probe_analyzer()
    probe_files = []
    try:
        test_file = '/tmp/test_target.txt'
        test_content = 'Hello, World!\n'
        Path(test_file).write_text(test_content)
        file_size = len(test_content)

        s = ws_connect('127.0.0.1', 9050, '/analyze')

        # Preserve the original valid request assertion.
        ws_send(s, json.dumps({'target_file': test_file}))
        resp1 = ws_recv(s)
        expected_prefix = f'ANALYSIS_RESULT:{file_size}_OK'
        assert resp1 is not None, 'No response received for valid request'
        assert resp1.strip() == expected_prefix, \
            f'Expected response starting with {expected_prefix}, got {resp1}'

        # Preserve the original malformed/missing-key assertion.
        ws_send(s, '{"bad": "data"}')
        resp2 = ws_recv(s)
        assert resp2 is not None, 'No response received for invalid JSON'
        assert resp2.strip() == 'ERROR', f'Expected ERROR for invalid JSON, got {resp2}'

        # Preserve the original nonexistent-file assertion.
        missing = Path('/tmp/does_not_exist_12345.txt')
        missing.unlink(missing_ok=True)
        ws_send(s, json.dumps({'target_file': str(missing)}))
        resp3 = ws_recv(s)
        assert resp3 is not None, 'No response received for non-existent file'
        assert resp3.strip() == 'ERROR', \
            f'Expected ERROR for non-existent file, got {resp3}'

        # Exercise unpredictable files consecutively on the same connection.
        expected_calls = []
        for i in range(4):
            path = Path('/tmp') / f'{prefix}{i}.bin'
            data = os.urandom(secrets.randbelow(180) + 1)
            path.write_bytes(data)
            probe_files.append(path)
            expected_calls.append([str(path)])

            ws_send(s, json.dumps({'target_file': str(path)}))
            response = ws_recv(s)
            digest = hashlib.sha256(data).hexdigest()
            expected = (
                f'ANALYSIS_RESULT:{len(data)}_OK\n'
                f'PROBE:{token}:{digest}:{len(data)}'
            )
            assert response is not None, f'No response for dynamic request {i}'
            assert response.strip() == expected, \
                f'Analyzer stdout was not returned for dynamic request {i}: {response!r}'

        s.close()

        assert log_path.is_file(), 'The service did not execute /app/build_analyzer'
        calls = [json.loads(line) for line in log_path.read_text().splitlines() if line]
        assert calls == expected_calls, \
            f'Analyzer was not invoked once per request with only target_file: {calls}'
    finally:
        for path in probe_files:
            path.unlink(missing_ok=True)
        log_path.unlink(missing_ok=True)
        restore_analyzer(backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
