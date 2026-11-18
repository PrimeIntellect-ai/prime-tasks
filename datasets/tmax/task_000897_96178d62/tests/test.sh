#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import socket
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest
import requests

REPO = Path('/home/user/telemetry_server')
SERVER = REPO / 'server'
ORACLE = Path('/app/telemetry_oracle')
INVALID_BYTES = [0x80, 0xBF, 0xC0, 0xC1, 0xF5, 0xF6, 0xFE, 0xFF]


def run_git(*args):
    return subprocess.run(
        ['git', *args], cwd=REPO, check=True, capture_output=True, text=True
    ).stdout.strip()


def parser_commit_hangs(commit):
    source = subprocess.run(
        ['git', 'show', f'{commit}:src/parser.c'],
        cwd=REPO, check=True, capture_output=True, text=True
    ).stdout
    harness = r'''
int main(void) {
    unsigned char value[2] = {0xff, 0};
    sanitize_utf8(value, 1);
    return value[0] == '?' ? 0 : 3;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = Path(td) / 'check.c'
        exe = Path(td) / 'check'
        src.write_text(source + '\n' + harness)
        subprocess.run(
            ['gcc', '-O0', '-o', str(exe), str(src)],
            check=True, capture_output=True, timeout=10
        )
        try:
            result = subprocess.run([str(exe)], timeout=0.5)
        except subprocess.TimeoutExpired:
            return True
        assert result.returncode == 0, f'Historical parser at {commit} behaved unexpectedly'
        return False


def derive_regression_commit():
    ref = 'refs/heads/master'
    try:
        run_git('show-ref', '--verify', '--quiet', ref)
    except subprocess.CalledProcessError:
        ref = 'HEAD'
    commits = run_git('rev-list', '--reverse', ref, '--', 'src/parser.c').splitlines()
    assert commits, 'No parser history found'
    previous_hangs = None
    transitions = []
    for commit in commits:
        hangs = parser_commit_hangs(commit)
        if previous_hangs is False and hangs is True:
            transitions.append(commit)
        previous_hangs = hangs
    assert len(transitions) == 1, f'Expected one parser regression transition, found {transitions}'
    return transitions[0]


def test_bad_commit_file():
    bad_commit_file = '/home/user/bad_commit.txt'
    assert os.path.isfile(bad_commit_file), f'File {bad_commit_file} does not exist.'
    with open(bad_commit_file, 'r') as f:
        sha = f.read().strip()
    assert len(sha) in (40, 7), f'Invalid Git SHA format in {bad_commit_file}: {sha}'
    try:
        subprocess.run(
            ['git', 'cat-file', '-e', f'{sha}^{{commit}}'],
            cwd=REPO, check=True, capture_output=True
        )
    except subprocess.CalledProcessError:
        pytest.fail(f'The commit SHA {sha} found in {bad_commit_file} is not a valid commit in the repository.')
    submitted = run_git('rev-parse', f'{sha}^{{commit}}')
    expected = derive_regression_commit()
    assert submitted == expected, f'{sha} is not the commit that introduced the parser regression'


def listener_pids(port):
    wanted = f'0100007F:{port:04X}'
    inodes = set()
    with open('/proc/net/tcp') as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1].upper() == wanted and fields[3] == '0A':
                inodes.add(fields[9])
    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except (OSError, PermissionError):
            continue
    return pids


def test_compiled_c_artifact_is_running():
    assert SERVER.is_file(), f'Compiled server artifact {SERVER} is missing'
    assert os.access(SERVER, os.X_OK), f'{SERVER} is not executable'
    with SERVER.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'The server artifact is not a native compiled ELF executable'
    if ORACLE.exists():
        assert SERVER.read_bytes() != ORACLE.read_bytes(), 'Submission is byte-identical to the reference binary'
    for port in (8080, 9090):
        pids = listener_pids(port)
        assert pids, f'No process is listening specifically on 127.0.0.1:{port}'
        assert any(
            os.path.exists(f'/proc/{pid}/exe') and os.path.samefile(f'/proc/{pid}/exe', SERVER)
            for pid in pids
        ), f'The listener on port {port} is not the compiled server artifact'


def test_fixed_parser_source_on_generated_inputs():
    parser = REPO / 'src/parser.c'
    assert parser.is_file(), 'src/parser.c is missing'
    rng = random.SystemRandom()
    cases = []
    for _ in range(24):
        data = bytearray(rng.randrange(0x20, 0x7f) for _ in range(rng.randrange(4, 40)))
        for _ in range(rng.randrange(1, min(7, len(data)) + 1)):
            data[rng.randrange(len(data))] = rng.choice(INVALID_BYTES)
        cases.append(bytes(data))
    lines = ['#include <string.h>', 'void sanitize_utf8(unsigned char *str, int len);', 'int main(void) {']
    for index, data in enumerate(cases):
        expected = bytes(b if b < 128 else ord('?') for b in data)
        values = ','.join(str(b) for b in data)
        wanted = ','.join(str(b) for b in expected)
        lines.append(f'unsigned char a{index}[] = {{{values}}};')
        lines.append(f'unsigned char e{index}[] = {{{wanted}}};')
        lines.append(f'sanitize_utf8(a{index}, {len(data)});')
        lines.append(f'if (memcmp(a{index}, e{index}, {len(data)}) != 0) return {index + 1};')
    lines.append('return 0; }')
    with tempfile.TemporaryDirectory() as td:
        harness = Path(td) / 'harness.c'
        exe = Path(td) / 'parser_test'
        harness.write_text('\n'.join(lines))
        subprocess.run(
            ['gcc', '-O0', '-o', str(exe), str(harness), str(parser)],
            cwd=REPO, check=True, capture_output=True, timeout=10
        )
        try:
            result = subprocess.run([str(exe)], capture_output=True, timeout=2)
        except subprocess.TimeoutExpired:
            pytest.fail('sanitize_utf8 still hangs on malformed input')
        assert result.returncode == 0, f'sanitize_utf8 failed generated case {result.returncode}'


def test_http_health_check():
    try:
        response = requests.get('http://127.0.0.1:8080/health', timeout=2)
        assert response.status_code == 200, f'Expected HTTP 200, got {response.status_code}'
        data = response.json()
        assert data.get('status') == 'ok', f"Expected {{'status': 'ok'}}, got {data}"
    except requests.RequestException as e:
        pytest.fail(f'HTTP health check failed: {e}')


def send_frame(payload, fragmented=False):
    with socket.create_connection(('127.0.0.1', 9090), timeout=2) as s:
        s.settimeout(2)
        auth = b'AUTH_TOKEN: 8a9b4c2d-1234\n'
        frame = struct.pack('<I', len(payload)) + payload
        if fragmented:
            wire = auth + frame
            for byte in wire:
                s.sendall(bytes([byte]))
        else:
            s.sendall(auth)
            s.sendall(frame)
        expected_len = len(b'ACK: ') + len(payload)
        response = bytearray()
        while len(response) < expected_len:
            chunk = s.recv(expected_len - len(response))
            if not chunk:
                break
            response.extend(chunk)
        return bytes(response)


def test_tcp_telemetry_protocol():
    payload = b'hello\xffworld'
    response = send_frame(payload)
    expected_response = b'ACK: hello?world'
    assert response == expected_response, f'Expected {expected_response}, got {response}'


def test_tcp_generated_malformed_payloads():
    rng = random.SystemRandom()
    for case in range(16):
        payload = bytearray(rng.randrange(0x21, 0x7f) for _ in range(rng.randrange(5, 55)))
        for _ in range(rng.randrange(1, min(9, len(payload)) + 1)):
            payload[rng.randrange(len(payload))] = rng.choice(INVALID_BYTES)
        payload = bytes(payload)
        expected = b'ACK: ' + bytes(b if b < 128 else ord('?') for b in payload)
        assert send_frame(payload, fragmented=(case == 0)) == expected


def test_tcp_requires_authentication():
    payload = b'unauthorized\xffpayload'
    frame = struct.pack('<I', len(payload)) + payload
    with socket.create_connection(('127.0.0.1', 9090), timeout=2) as s:
        s.settimeout(0.5)
        s.sendall(frame)
        try:
            response = s.recv(1024)
        except socket.timeout:
            response = b''
    assert response != b'ACK: unauthorized?payload', 'Server accepted telemetry without the required token'
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
