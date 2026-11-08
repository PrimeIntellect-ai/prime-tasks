#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import collections
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time

import pytest
import redis

RAW = Path('/app/data/raw_payloads.txt')
AGGREGATOR = Path('/app/aggregator.sh')
MARKER = 'EICAR-STANDARD-ANTIVIRUS-TEST-FILE'


def find_delta_debugging_script():
    roots = [Path('/app'), Path('/home'), Path('/root'), Path('/opt'), Path('/tmp')]
    excluded = {
        Path('/app/c2_server.py'),
        Path('/app/aggregator.sh'),
        Path('/app/start_services.sh'),
        Path('/tmp/test_final_state.py'),
        Path('/tmp/capture_server.py'),
    }
    candidates = []

    for root in roots:
        if not root.exists():
            continue
        try:
            paths = root.rglob('*')
            for path in paths:
                try:
                    if path in excluded or not path.is_file() or path.is_symlink():
                        continue
                    if path.stat().st_size > 1024 * 1024:
                        continue
                    if path.suffix.lower() not in {'.py', '.sh', '.bash', '.pl', '.rb'} and not os.access(path, os.X_OK):
                        continue
                    text = path.read_text(errors='ignore').lower()
                except (OSError, UnicodeError):
                    continue

                identifies_input = 'raw_payloads.txt' in text
                probes_failure = any(term in text for term in (
                    'curl', 'http://', 'requests.', 'urllib', 'status_code',
                    'http 500', 'crash', 'poison', 'eicar'
                ))
                divides_search_space = any(term in text for term in (
                    'bisect', 'binary search', 'midpoint', ' mid ', 'mid=',
                    'mid =', 'half', '// 2', 'delta', 'split', 'head', 'tail'
                ))
                if identifies_input and probes_failure and divides_search_space:
                    candidates.append(str(path))
        except OSError:
            continue

    assert candidates, (
        'No delta-debugging/bisection script was found. The submission must leave a script '
        'that targets raw_payloads.txt and divides the search space while testing for failure.'
    )


def kill_c2_processes():
    victims = []
    for proc in Path('/proc').glob('[0-9]*'):
        try:
            cmdline = (proc / 'cmdline').read_bytes()
            pid = int(proc.name)
        except (OSError, ValueError):
            continue
        if b'/app/c2_server.py' in cmdline and pid != os.getpid():
            victims.append(pid)

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_port(port, process, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail('The capture server exited before it could accept connections')
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f'Timed out waiting for port {port}')


def restart_real_c2():
    kill_c2_processes()
    log = open('/app/c2.log', 'ab', buffering=0)
    subprocess.Popen(
        [sys.executable, '/app/c2_server.py'],
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
    )


def test_complete_pipeline_repair():
    assert RAW.is_file(), 'raw_payloads.txt is missing'
    lines = RAW.read_text().splitlines()
    assert len(lines) == 10000, f'Expected 10,000 source lines, found {len(lines)}'

    poison_positions = [i + 1 for i, line in enumerate(lines) if MARKER in line]
    assert poison_positions == [7342], (
        f'The source data was altered: expected one poison payload at line 7342, found {poison_positions}'
    )
    assert lines[7341] == 'EICAR-STANDARD-ANTIVIRUS-TEST-FILE-12345'

    for number, line in enumerate(lines, 1):
        if number == 7342:
            continue
        try:
            decoded = base64.b64decode(line, validate=True)
        except Exception as exc:
            pytest.fail(f'Non-poison source line {number} is not valid base64: {exc}')
        assert len(decoded) == 16, f'Non-poison source line {number} was altered'

    expected = [line for line in lines if MARKER not in line]
    assert len(expected) == 9999

    assert AGGREGATOR.is_file(), '/app/aggregator.sh is missing'
    assert os.access(AGGREGATOR, os.X_OK), '/app/aggregator.sh is not executable'
    assert AGGREGATOR.read_bytes().startswith(b'#!'), '/app/aggregator.sh is not a script'
    find_delta_debugging_script()

    try:
        r = redis.Redis(host='localhost', port=6379, db=0)
        r.ping()
        keys = r.keys('payload:*')
        count = len(keys)
    except redis.exceptions.ConnectionError:
        pytest.fail('Failed to connect to Redis on localhost:6379. Ensure the Redis server is running.')
    except Exception as exc:
        pytest.fail(f'An error occurred while communicating with Redis: {exc}')

    threshold = 9999
    assert count == threshold, (
        f'Metric threshold failed: Expected exactly {threshold} payloads in Redis, but found {count}.'
    )

    stored = [value.decode('utf-8') for value in r.mget(keys)]
    assert all(MARKER not in value for value in stored), 'The poison payload was stored in Redis'
    assert collections.Counter(stored) == collections.Counter(expected), (
        'Redis payload contents do not exactly match all non-poison source lines'
    )

    capture_path = Path('/tmp/captured_payloads.txt')
    capture_path.unlink(missing_ok=True)
    Path('/tmp/capture_server.py').write_text(r'''import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import sys

output = sys.argv[1]

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        with open(output, 'ab') as f:
            f.write(base64.b64encode(body) + b'\n')
        self.send_response(200)
        self.send_header('Content-Length', '2')
        self.end_headers()
        self.wfile.write(b'OK')

    def log_message(self, fmt, *args):
        pass

ThreadingHTTPServer(('127.0.0.1', 5000), Handler).serve_forever()
''')

    kill_c2_processes()
    capture = subprocess.Popen(
        [sys.executable, '/tmp/capture_server.py', str(capture_path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_port(5000, capture)
        result = subprocess.run(
            [str(AGGREGATOR)],
            cwd='/app',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, (
            f'aggregator.sh failed when exercised: {result.stderr[-1000:]}'
        )
    finally:
        if capture.poll() is None:
            capture.terminate()
            try:
                capture.wait(timeout=5)
            except subprocess.TimeoutExpired:
                capture.kill()
                capture.wait(timeout=5)
        restart_real_c2()

    assert capture_path.is_file(), 'The aggregator sent no requests'
    captured = [
        base64.b64decode(line).decode('utf-8')
        for line in capture_path.read_bytes().splitlines()
    ]
    assert captured == expected, (
        'When the server accepts every request, aggregator.sh must send every non-poison line '
        'in order and must never send the poison line'
    )
    r.ping()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
