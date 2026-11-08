#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

PROJECT = Path('/home/user/mock_api')
CONFIG = Path('/home/user/nginx.conf')
BACKEND = 'http://127.0.0.1:9000/legacy'
PROXY = 'http://127.0.0.1:8080/legacy'
RUST_PROCESS = None
NGINX_PROCESS = None


def listening_inodes(port):
    result = set()
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
                if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                    result.add(fields[9])
    return result


def pid_owns_port(pid, port):
    inodes = listening_inodes(port)
    if not inodes:
        return False
    try:
        links = [os.readlink(str(p)) for p in Path(f'/proc/{pid}/fd').iterdir()]
    except (OSError, FileNotFoundError, PermissionError):
        return False
    return any(link.startswith('socket:[') and link[8:-1] in inodes for link in links)


def pids_owning_port(port):
    inodes = listening_inodes(port)
    owners = set()
    if not inodes:
        return owners
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                link = os.readlink(str(fd))
                if link.startswith('socket:[') and link[8:-1] in inodes:
                    owners.add(int(proc.name))
                    break
        except (OSError, FileNotFoundError, PermissionError):
            pass
    return owners


def stop_pids(pids):
    pids = {p for p in pids if p != os.getpid()}
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while pids and time.time() < deadline:
        pids = {p for p in pids if Path(f'/proc/{p}').exists()}
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(port, timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f'Port {port} did not become available')


def post(url, payload):
    req = urllib.request.Request(url, data=payload, method='POST')
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, dict(response.getheaders()), response.read().decode('utf-8').strip()


def expected_for(payload):
    tallies = {chr(c): 0 for c in range(ord('A'), ord('Z') + 1)}
    output = []
    state = 'Idle'
    for ch in payload.decode('ascii'):
        if ch in ' \t\n\r':
            continue
        if state == 'Idle':
            if ch == '+':
                state = 'ExpectAdd'
            elif ch == '-':
                state = 'ExpectSub'
            elif ch == '?':
                state = 'ExpectQuery'
            else:
                break
        elif 'A' <= ch <= 'Z':
            if state == 'ExpectAdd':
                tallies[ch] += 1
            elif state == 'ExpectSub':
                tallies[ch] -= 1
            else:
                output.append(str(tallies[ch]))
            state = 'Idle'
        else:
            break
    return ','.join(output)


@pytest.fixture(scope='session', autouse=True)
def build_and_start_submission():
    global RUST_PROCESS, NGINX_PROCESS

    assert PROJECT.exists() and PROJECT.is_dir(), 'Rust project directory /home/user/mock_api does not exist.'
    assert CONFIG.exists() and CONFIG.is_file(), 'Nginx config /home/user/nginx.conf does not exist.'
    manifest = PROJECT / 'Cargo.toml'
    assert manifest.is_file(), 'Rust project is missing Cargo.toml.'

    sources = [p for p in PROJECT.rglob('*.rs') if 'target' not in p.parts]
    assert sources, 'Rust project contains no Rust source files.'
    source_text = '\n'.join(p.read_text(errors='replace') for p in sources)
    assert re.search(r'std\s*::\s*net', source_text), 'Server source does not use std::net.'

    metadata_run = subprocess.run(
        ['cargo', 'metadata', '--format-version=1', '--manifest-path', str(manifest)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert metadata_run.returncode == 0, f'cargo metadata failed: {metadata_run.stderr}'
    metadata = json.loads(metadata_run.stdout)
    forbidden = {'hyper', 'actix-web', 'actix_web', 'axum', 'warp', 'rocket', 'tiny_http'}
    submitted_packages = [p for p in metadata['packages'] if Path(p['manifest_path']).is_relative_to(PROJECT)]
    assert submitted_packages, 'Cargo metadata did not identify the submitted project.'
    dependencies = {d['name'].lower() for p in submitted_packages for d in p.get('dependencies', [])}
    assert not (dependencies & forbidden), f'External HTTP crate is prohibited: {sorted(dependencies & forbidden)}'

    build = subprocess.run(
        ['cargo', 'build', '--manifest-path', str(manifest), '--message-format=json'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert build.returncode == 0, f'Rust project failed to build: {build.stderr}'
    executables = []
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get('reason') == 'compiler-artifact' and message.get('executable'):
            if 'bin' in message.get('target', {}).get('kind', []):
                executables.append(message['executable'])
    assert executables, 'Cargo project did not produce a binary executable.'

    config_text = CONFIG.read_text(errors='replace')
    uncommented = re.sub(r'#.*', '', config_text)
    assert re.search(r'listen\s+127\.0\.0\.1:8080\b', uncommented), 'Nginx config must listen on 127.0.0.1:8080.'
    assert re.search(r'location\s+(?:=\s*)?/legacy(?:\s|\{|/)', uncommented), 'Nginx config has no /legacy location.'
    assert re.search(r'proxy_pass\s+http://127\.0\.0\.1:9000\s*;', uncommented), 'Nginx config does not proxy to the Rust server.'
    assert re.search(r'add_header\s+X-Mock-Proxy\s+["\']?Active["\']?\s*;', uncommented, re.I), 'Nginx config does not add X-Mock-Proxy: Active.'

    nginx_test = subprocess.run(
        ['nginx', '-t', '-c', str(CONFIG)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert nginx_test.returncode == 0, f'Nginx configuration is invalid: {nginx_test.stderr}'

    stop_pids(pids_owning_port(9000))
    RUST_PROCESS = subprocess.Popen(
        [executables[-1]], cwd=str(PROJECT),
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    wait_for_port(9000)
    assert RUST_PROCESS.poll() is None, 'Built Rust server exited during startup.'
    assert pid_owns_port(RUST_PROCESS.pid, 9000), 'The built Rust executable itself is not listening on port 9000.'

    nginx_pids = set()
    for proc in Path('/proc').iterdir():
        if proc.name.isdigit():
            try:
                if (proc / 'comm').read_text().strip() == 'nginx':
                    nginx_pids.add(int(proc.name))
            except OSError:
                pass
    stop_pids(nginx_pids | pids_owning_port(8080))
    NGINX_PROCESS = subprocess.Popen(
        ['nginx', '-c', str(CONFIG)],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    wait_for_port(8080)
    owners = pids_owning_port(8080)
    assert owners, 'No process owns the Nginx listening port.'
    assert any(Path(f'/proc/{pid}/comm').read_text().strip() == 'nginx' for pid in owners), 'Port 8080 is not being served by Nginx.'
    yield


def test_files_exist():
    assert os.path.exists('/home/user/mock_api'), 'Rust project directory /home/user/mock_api does not exist.'
    assert os.path.exists('/home/user/nginx.conf'), 'Nginx config /home/user/nginx.conf does not exist.'


def test_nginx_and_rust_server_integration():
    url = PROXY

    payload1 = b'+A+A+B-A?A?B+C-C?C'
    try:
        status, headers, body = post(url, payload1)
        assert status == 200, f'Expected HTTP 200, got {status}'
        assert 'X-Mock-Proxy' in headers, 'Missing X-Mock-Proxy header in response.'
        assert headers['X-Mock-Proxy'] == 'Active', f"Expected X-Mock-Proxy: Active, got {headers['X-Mock-Proxy']}"
        assert body == '1,1,0', f"Expected body '1,1,0', got '{body}'"
    except urllib.error.URLError as e:
        assert False, f'Failed to connect to Nginx at {url}: {e}'

    payload2 = b' + A \n+ B - A ?A \t ?B -C -C ?C'
    try:
        _, _, body = post(url, payload2)
        assert body == '0,1,-2', f"Expected body '0,1,-2' (ignoring whitespace), got '{body}'"
    except urllib.error.URLError as e:
        assert False, f'Failed to connect to Nginx at {url}: {e}'

    payload3 = b'+A+B?A?B ! +A?A'
    try:
        _, _, body = post(url, payload3)
        assert body == '1,1', f"Expected body '1,1' (aborted before second ?A), got '{body}'"
    except urllib.error.URLError as e:
        assert False, f'Failed to connect to Nginx at {url}: {e}'


def test_randomized_state_machine_through_backend_and_proxy():
    rng = secrets.SystemRandom()
    whitespace = ['', ' ', '\t', '\n', ' \t']

    payloads = []
    for case in range(16):
        pieces = []
        for _ in range(rng.randint(25, 60)):
            op = rng.choice('++--???')
            letter = rng.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
            pieces.extend((rng.choice(whitespace), op, rng.choice(whitespace), letter, rng.choice(whitespace)))
        if case % 2:
            invalid = rng.choice(['!', '7', 'a', '/', '@'])
            pieces.extend((invalid, '+Z+Z?Z'))
        payloads.append(''.join(pieces).encode('ascii'))

    # Exercise invalid transitions specifically, with randomized prefixes/suffixes.
    for invalid_sequence in ('+a', '-?', '??', 'A', '--'):
        letter = rng.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
        payloads.append((f'+{letter}?{letter}' + invalid_sequence + f'+{letter}?{letter}').encode('ascii'))

    for payload in payloads:
        expected = expected_for(payload)
        direct_status, _, direct_body = post(BACKEND, payload)
        proxy_status, proxy_headers, proxy_body = post(PROXY, payload)
        assert direct_status == 200 and proxy_status == 200
        assert direct_body == expected, f'Backend returned {direct_body!r}, expected {expected!r} for {payload!r}'
        assert proxy_body == expected, f'Proxy returned {proxy_body!r}, expected {expected!r} for {payload!r}'
        assert proxy_headers.get('X-Mock-Proxy') == 'Active'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
