#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import re
import signal
import subprocess
import time
import uuid
from pathlib import Path

import pytest

SOURCE = Path('/home/user/deploy_gate.c')
BINARY = Path('/home/user/deploy_gate')
PAYLOAD = Path('/app/payload.bin')
IMAGE = Path('/app/release_tag.png')


def calculate_xor_checksum(filepath):
    checksum = 0
    with open(filepath, 'rb') as f:
        while byte := f.read(1):
            checksum ^= byte[0]
    return checksum


def extract_metadata():
    result = subprocess.run(
        ['tesseract', str(IMAGE), 'stdout'],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    version_match = re.search(r'VERSION:\s*(\S+)', result.stdout)
    token_match = re.search(r'TOKEN:\s*(\S+)', result.stdout)
    assert version_match, f'Could not extract VERSION from image OCR: {result.stdout!r}'
    assert token_match, f'Could not extract TOKEN from image OCR: {result.stdout!r}'
    version = version_match.group(1)
    token = token_match.group(1)
    # Preserve the original verifier's expected metadata assertions.
    assert version == '4.12.3', f'Unexpected release version in image: {version!r}'
    assert token == 'z9k-Delta-44', f'Unexpected token in image: {token!r}'
    return version, token


def listener_pids(port=8080):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10:
                local = fields[1]
                state = fields[3]
                try:
                    local_port = int(local.rsplit(':', 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if local_port == port and state == '0A':
                    inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def assert_listener_is_binary():
    pids = listener_pids()
    assert pids, 'No process is listening on port 8080'
    matching = []
    for pid in pids:
        try:
            if os.path.samefile(f'/proc/{pid}/exe', BINARY):
                matching.append(pid)
        except OSError:
            pass
    assert matching, f'Port 8080 listener is not the executable {BINARY}; listener PIDs: {sorted(pids)}'


def request(path='/deploy', authorization=None):
    headers = {}
    if authorization is not None:
        headers['Authorization'] = authorization
    connection = http.client.HTTPConnection('127.0.0.1', 8080, timeout=2)
    try:
        connection.request('GET', path, headers=headers)
        response = connection.getresponse()
        body = response.read()
        return response.status, response.version, dict(response.getheaders()), body
    finally:
        connection.close()


def assert_unauthorized(authorization=None):
    status, http_version, _, _ = request(authorization=authorization)
    assert status == 401, f'Expected HTTP 401 Unauthorized, got {status}'
    assert http_version == 11, 'Unauthorized response was not HTTP/1.1'


def assert_authorized(version, token, expected_checksum):
    status, http_version, headers, body = request(authorization=f'Bearer {token}')
    assert status == 200, f'Expected HTTP 200 OK for valid token, got {status}'
    assert http_version == 11, 'Authorized response was not HTTP/1.1'
    content_type = headers.get('Content-Type') or headers.get('content-type')
    assert content_type is not None, 'Authorized response lacks Content-Type'
    assert content_type.split(';', 1)[0].strip().lower() == 'application/json', \
        f'Expected Content-Type application/json, got {content_type!r}'
    try:
        data = json.loads(body.decode('utf-8'))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        pytest.fail(f'Response body is not valid JSON: {exc}')
    assert data.get('status') == 'ready', f"Expected status 'ready', got {data.get('status')}"
    assert data.get('version') == version, f"Expected version '{version}', got {data.get('version')}"
    assert data.get('checksum') == expected_checksum, \
        f"Expected checksum {expected_checksum}, got {data.get('checksum')}"


def wait_for_server(process, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            stdout, stderr = process.communicate(timeout=1)
            pytest.fail(f'Rebuilt deployment gate exited early ({process.returncode}): {stdout!r} {stderr!r}')
        try:
            connection = http.client.HTTPConnection('127.0.0.1', 8080, timeout=0.25)
            connection.request('GET', '/deploy')
            response = connection.getresponse()
            response.read()
            connection.close()
            return
        except OSError:
            time.sleep(0.1)
    pytest.fail('Rebuilt deployment gate did not begin listening on port 8080')


def stop_current_listener():
    pids = listener_pids()
    assert pids, 'Deployment gate listener disappeared before rebuild test'
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    assert not listener_pids(), 'Existing listener could not be stopped for source rebuild test'


def test_complete_c_deployment_gate():
    assert SOURCE.is_file() and not SOURCE.is_symlink(), f'{SOURCE} must be a regular C source file'
    assert SOURCE.stat().st_size > 0, f'{SOURCE} is empty'
    assert BINARY.is_file() and not BINARY.is_symlink(), f'{BINARY} must be a regular executable file'
    assert os.access(BINARY, os.X_OK), f'{BINARY} is not executable'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', f'{BINARY} is not an ELF executable'

    version, token = extract_metadata()
    original_checksum = calculate_xor_checksum(PAYLOAD)

    # Preserve and extend the original live-server checks.
    assert_listener_is_binary()
    assert_unauthorized()
    assert_authorized(version, token, original_checksum)
    assert_unauthorized(f'Bearer invalid-{uuid.uuid4().hex}')
    assert_unauthorized(f'Bearer {token}-{uuid.uuid4().hex}')
    assert_unauthorized(token)
    # Confirm the accept loop continues serving requests.
    assert_authorized(version, token, original_checksum)
    assert_authorized(version, token, original_checksum)

    rebuilt = Path('/tmp/deploy_gate.rebuilt')
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', str(SOURCE), '-o', str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, \
        f'C source did not compile successfully: {compile_result.stdout}\n{compile_result.stderr}'
    assert rebuilt.read_bytes()[:4] == b'\x7fELF'

    original_payload = PAYLOAD.read_bytes()
    process = None
    try:
        stop_current_listener()
        os.replace(rebuilt, BINARY)
        BINARY.chmod(0o755)

        # Use verifier-generated payload bytes so a hardcoded checksum cannot pass.
        while True:
            challenge_payload = os.urandom(6149)
            challenge_checksum = 0
            for byte in challenge_payload:
                challenge_checksum ^= byte
            if challenge_checksum != original_checksum:
                break
        PAYLOAD.write_bytes(challenge_payload)

        process = subprocess.Popen(
            [str(BINARY)],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        wait_for_server(process)
        assert_listener_is_binary()
        assert_unauthorized()
        assert_unauthorized(f'Bearer wrong-{uuid.uuid4().hex}')
        assert_unauthorized(f'Bearer {token}x')
        assert_authorized(version, token, challenge_checksum)
        assert_authorized(version, token, challenge_checksum)
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=1)
        PAYLOAD.write_bytes(original_payload)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
