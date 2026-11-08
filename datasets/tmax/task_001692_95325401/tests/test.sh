#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import json
import os
import re
import socket
import subprocess
import tempfile
import urllib.error
import urllib.request
import uuid

import pytest


def running_process(predicate):
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ').decode(errors='replace')
            with open(f'/proc/{entry}/comm', 'r') as f:
                comm = f.read().strip()
            if predicate(comm, cmdline):
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return False


def get_json(url):
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f'Expected HTTP 200, got {response.status}'
            server = response.headers.get('Server', '')
            data = response.read().decode('utf-8')
    except urllib.error.URLError as e:
        pytest.fail(f'Failed to connect to {url}: {e}')
    try:
        return json.loads(data), server
    except json.JSONDecodeError:
        pytest.fail(f'Response is not valid JSON: {data}')


def test_services_running_and_routing():
    """Verify the configured Nginx, backend, and Redis services independently and end-to-end."""
    config = '/app/staging/nginx/nginx.conf'
    assert os.path.isfile(config), f'Nginx configuration missing at {config}'
    check = subprocess.run(['nginx', '-t', '-c', config], capture_output=True, text=True)
    assert check.returncode == 0, f'Nginx configuration is invalid:\n{check.stdout}\n{check.stderr}'
    with open(config, 'r') as f:
        text = f.read()
    assert re.search(r'listen\s+8080\s*;', text), 'Nginx config does not listen on port 8080'
    assert re.search(r'location\s+/?api/', text), 'Nginx config has no /api/ location'
    assert re.search(r'proxy_pass\s+http://127\.0\.0\.1:8081/?\s*;', text), \
        'Nginx config does not proxy /api/ to 127.0.0.1:8081'

    assert running_process(lambda comm, cmd: comm == 'nginx'), 'No Nginx process is running'
    assert running_process(lambda comm, cmd: '/app/staging/backend/api_server' in cmd), \
        'The specified backend service is not running'
    assert running_process(lambda comm, cmd: comm.startswith('redis-server') or 'redis-server' in cmd), \
        'No Redis server process is running'

    with socket.create_connection(('127.0.0.1', 6379), timeout=5) as sock:
        sock.sendall(b'*1\r\n$4\r\nPING\r\n')
        redis_reply = sock.recv(128)
    assert redis_reply.startswith(b'+PONG'), f'Redis did not answer PING: {redis_reply!r}'

    direct, _ = get_json('http://127.0.0.1:8081/api/health')
    assert direct.get('status') == 'ok', f"Expected direct backend status 'ok', got {direct.get('status')}"
    assert direct.get('redis') == 'connected', \
        f"Expected direct backend Redis status 'connected', got {direct.get('redis')}"

    routed, server = get_json('http://127.0.0.1:8080/api/health')
    assert server.lower().startswith('nginx'), f'Request on port 8080 was not served through Nginx: {server!r}'
    assert routed.get('status') == 'ok', f"Expected status 'ok', got {routed.get('status')}"
    assert routed.get('redis') == 'connected', f"Expected redis 'connected', got {routed.get('redis')}"


def test_cracked_pin():
    pin_file = '/home/user/cracked_pin.txt'
    assert os.path.isfile(pin_file), f'Cracked PIN file missing at {pin_file}'
    with open(pin_file, 'r') as f:
        pin = f.read().strip()
    assert pin == '4815', f"Expected PIN '4815', but got '{pin}'"


def run_detector_exact(detector_bin, corpus_dir, expected):
    proc = subprocess.run([detector_bin, corpus_dir], capture_output=True, text=True, timeout=20)
    assert proc.returncode == 0, f'Detector failed on {corpus_dir}:\n{proc.stderr}'
    actual = proc.stdout.splitlines()
    assert collections.Counter(actual) == collections.Counter(expected), \
        f'Detector output must contain exactly one correctly formatted line per .txt file. Expected {expected!r}, got {actual!r}'


def test_detector_compilation_and_classification():
    detector_dir = '/home/user/detector'
    assert os.path.isdir(detector_dir), f'Detector project directory missing at {detector_dir}'
    cargo_toml = os.path.join(detector_dir, 'Cargo.toml')
    assert os.path.isfile(cargo_toml), f'Cargo.toml missing in {detector_dir}'

    build_proc = subprocess.run(
        ['cargo', 'build', '--release'], cwd=detector_dir,
        capture_output=True, text=True, timeout=180
    )
    assert build_proc.returncode == 0, \
        f'Failed to compile detector:\nSTDOUT:\n{build_proc.stdout}\nSTDERR:\n{build_proc.stderr}'

    detector_bin = os.path.join(detector_dir, 'target', 'release', 'detector')
    assert os.path.isfile(detector_bin), f'Compiled detector binary missing at {detector_bin}'
    assert os.access(detector_bin, os.X_OK), f'Detector binary at {detector_bin} is not executable'

    evil_dir = '/app/verifier/corpus/evil'
    clean_dir = '/app/verifier/corpus/clean'
    assert os.path.isdir(evil_dir), f'Evil corpus directory missing at {evil_dir}'
    assert os.path.isdir(clean_dir), f'Clean corpus directory missing at {clean_dir}'
    evil_files = sorted(f for f in os.listdir(evil_dir) if f.endswith('.txt'))
    clean_files = sorted(f for f in os.listdir(clean_dir) if f.endswith('.txt'))
    run_detector_exact(detector_bin, evil_dir, [f'[MALICIOUS] {f}' for f in evil_files])
    run_detector_exact(detector_bin, clean_dir, [f'[CLEAN] {f}' for f in clean_files])

    # Create an unpredictable corpus only after the agent has finished. Labels are
    # derived from the required detection rules, not from filenames or directories.
    with tempfile.TemporaryDirectory(prefix='detector-hidden-') as hidden:
        names = [uuid.uuid4().hex + '.txt' for _ in range(7)]
        method = 'PATCH'
        uri = '/api/' + uuid.uuid4().hex
        valid_hash = hashlib.md5(('4815' + method + uri).encode()).hexdigest()
        invalid_hash = hashlib.md5(('0000' + method + uri).encode()).hexdigest()
        payloads = [
            (names[0], f'{method} {uri} HTTP/1.1\nHost: example\nX-Backdoor-Auth: {valid_hash}\n', 'MALICIOUS'),
            (names[1], f'{method} {uri} HTTP/1.1\nHost: example\nX-Backdoor-Auth: {invalid_hash}\n', 'CLEAN'),
            (names[2], 'POST /search HTTP/1.1\n\nq=abc UNION SELECT password FROM users\n', 'MALICIOUS'),
            (names[3], "POST /login HTTP/1.1\n\nuser=' OR '1'='1\n", 'MALICIOUS'),
            (names[4], 'POST /comment HTTP/1.1\n\n<img src=x onerror=alert(1)>\n', 'MALICIOUS'),
            (names[5], 'GET /docs HTTP/1.1\n\nThe word selection is harmless.\n', 'CLEAN'),
            (names[6], 'POST /comment HTTP/1.1\n\nWelcome, ordinary user.\n', 'CLEAN'),
        ]
        expected = []
        for filename, content, label in payloads:
            with open(os.path.join(hidden, filename), 'w') as f:
                f.write(content)
            expected.append(f'[{label}] {filename}')
        with open(os.path.join(hidden, uuid.uuid4().hex + '.bin'), 'w') as f:
            f.write('<script>this non-txt file must be ignored</script>')
        run_detector_exact(detector_bin, hidden, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
