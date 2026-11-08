#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid

import pytest

URL = 'http://localhost:8080/analyze'


def nginx_config():
    result = subprocess.run(
        ['nginx', '-T'], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f'nginx -T failed:\n{result.stderr}'
    text = result.stdout + '\n' + result.stderr
    return re.sub(r'#.*', '', text)


def request(url, timeout=2):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read()


def duration_seconds(value, unit):
    multiplier = {'ms': 0.001, 's': 1, 'm': 60, 'h': 3600, 'd': 86400}[unit]
    return int(value) * multiplier


def test_services_socket_and_cache_configuration():
    config = nginx_config()

    assert re.search(r'\blisten\s+[^;]*\b8080\b[^;]*;', config), 'Nginx is not configured to listen on port 8080.'
    assert re.search(r'\bproxy_cache_path\s+[^;]+;', config), 'No proxy_cache_path is configured.'
    assert re.search(r'\bproxy_cache\s+(?!off\b)[^;]+;', config), 'proxy_cache is not enabled.'

    valid_directives = re.findall(r'\bproxy_cache_valid\s+([^;]+);', config)
    assert valid_directives, 'No proxy_cache_valid duration is configured.'
    durations = []
    for directive in valid_directives:
        for value, unit in re.findall(r'(?<!\w)(\d+)(ms|s|m|h|d)\b', directive):
            durations.append(duration_seconds(value, unit))
    assert durations and max(durations) >= 10, 'The configured proxy cache validity is less than 10 seconds.'

    gunicorn = subprocess.run(
        ['pgrep', '-af', 'gunicorn'], capture_output=True, text=True
    )
    assert gunicorn.returncode == 0 and gunicorn.stdout.strip(), 'Gunicorn is not running.'
    assert subprocess.run(['pgrep', '-x', 'nginx'], capture_output=True).returncode == 0, 'Nginx is not running.'

    binds = re.findall(r'(?:--bind(?:=|\s+))unix:([^\s]+)', gunicorn.stdout)
    assert binds, f'Running Gunicorn is not bound to a Unix socket:\n{gunicorn.stdout}'
    shared = [path for path in binds if path in config and os.path.exists(path)]
    assert shared, 'Nginx and the running Gunicorn process do not reference the same existing Unix socket.'


def test_nginx_caching_metric():
    """Retain the original 100-request performance assertion."""
    status, body = request(URL)
    assert status == 200
    assert body == b'Analysis complete\n', 'The endpoint did not return the vendored application response.'

    start = time.time()
    for i in range(100):
        try:
            status, body = request(URL)
            assert status == 200, f'Request {i+1}/100 failed: Expected 200 OK, got {status}'
            assert body == b'Analysis complete\n'
        except urllib.error.URLError as exc:
            pytest.fail(f'Request {i+1}/100 failed: {exc}. Is Nginx/Gunicorn running and correctly configured?')

    duration = time.time() - start
    assert duration <= 2.0, (
        f'Caching metric failed: 100 requests took {duration:.2f}s. '
        'Expected <= 2.0s. Check your Nginx proxy_cache configuration.'
    )


def test_proxy_reaches_unix_upstream_and_serves_cached_copy():
    """Use an unpredictable upstream response, then remove the upstream and require a cache hit."""
    config = nginx_config()
    gunicorn = subprocess.run(['pgrep', '-af', 'gunicorn'], capture_output=True, text=True, check=True).stdout
    binds = re.findall(r'(?:--bind(?:=|\s+))unix:([^\s]+)', gunicorn)
    shared = [path for path in binds if path in config and os.path.exists(path)]
    assert shared
    sock_path = shared[0]

    # Remove old cache entries so the first challenge response must reach our upstream.
    for cache_path in re.findall(r'\bproxy_cache_path\s+([^;\s]+)', config):
        if os.path.isabs(cache_path) and cache_path != '/' and os.path.isdir(cache_path):
            for name in os.listdir(cache_path):
                path = os.path.join(cache_path, name)
                try:
                    if os.path.isdir(path) and not os.path.islink(path):
                        shutil.rmtree(path)
                    else:
                        os.unlink(path)
                except FileNotFoundError:
                    pass

    backup = f'{sock_path}.verifier-{uuid.uuid4().hex}'
    payload = f'verifier-{uuid.uuid4().hex}\n'.encode()
    query = uuid.uuid4().hex
    stop = threading.Event()
    listener = None
    thread = None

    def serve():
        while not stop.is_set():
            try:
                conn, _ = listener.accept()
            except (OSError, socket.timeout):
                continue
            try:
                conn.settimeout(1)
                data = b''
                while b'\r\n\r\n' not in data and len(data) < 65536:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                response = (
                    b'HTTP/1.1 200 OK\r\n'
                    b'Content-Type: text/plain\r\n'
                    b'Cache-Control: public, max-age=30\r\n'
                    + f'Content-Length: {len(payload)}\r\n'.encode()
                    + b'Connection: close\r\n\r\n'
                    + payload
                )
                conn.sendall(response)
            finally:
                conn.close()

    try:
        os.rename(sock_path, backup)
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(sock_path)
        listener.listen(100)
        listener.settimeout(0.2)
        thread = threading.Thread(target=serve, daemon=True)
        thread.start()

        challenge_url = f'{URL}?verifier={query}'
        status, first = request(challenge_url)
        assert status == 200 and first == payload, 'Nginx did not proxy the unpredictable response from the configured Unix upstream.'

        stop.set()
        listener.close()
        listener = None
        thread.join(timeout=2)
        os.unlink(sock_path)

        start = time.time()
        status, cached = request(challenge_url)
        elapsed = time.time() - start
        assert status == 200 and cached == payload, 'The response was not available after the upstream socket was removed; proxy caching is not working.'
        assert elapsed < 1.0, f'The cached response took {elapsed:.2f}s to return.'
    finally:
        stop.set()
        if listener is not None:
            listener.close()
        if thread is not None:
            thread.join(timeout=2)
        try:
            if os.path.exists(sock_path):
                os.unlink(sock_path)
        finally:
            if os.path.exists(backup):
                os.rename(backup, sock_path)


def test_verify_capacity_script():
    """Retain execution checking and also verify the required workload is implemented."""
    script_path = '/home/user/verify_capacity.py'
    assert os.path.isfile(script_path), f'Task automation script {script_path} is missing.'

    source = open(script_path, encoding='utf-8').read()
    try:
        tree = ast.parse(source, filename=script_path)
    except SyntaxError as exc:
        pytest.fail(f'{script_path} is not valid Python: {exc}')

    constants = [node.value for node in ast.walk(tree) if isinstance(node, ast.Constant)]
    assert URL in constants or URL in source, 'The script does not target http://localhost:8080/analyze.'
    assert 50 in constants, 'The script does not define the required workload of 50 requests.'
    assert 200 in constants, 'The script does not check explicitly for HTTP 200.'

    call_names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name):
                call_names.append(func.id)
            elif isinstance(func, ast.Attribute):
                call_names.append(func.attr)

    concurrency_imported = any(
        isinstance(node, (ast.Import, ast.ImportFrom)) and any(
            alias.name.split('.')[0] in {'concurrent', 'threading', 'asyncio', 'multiprocessing'}
            for alias in node.names
        )
        for node in ast.walk(tree)
    )
    assert concurrency_imported, 'The script does not import a concurrency facility.'
    assert set(call_names) & {'map', 'submit', 'gather', 'create_task', 'start', 'starmap', 'imap', 'imap_unordered'}, (
        'The script does not schedule requests concurrently.'
    )

    checks_status = any(
        isinstance(node, ast.Attribute) and node.attr in {'status', 'status_code'}
        for node in ast.walk(tree)
    ) or 'getcode' in call_names
    checks_status = checks_status or 'raise_for_status' in call_names
    assert checks_status, 'The script never examines HTTP response status.'
    assert any(isinstance(node, (ast.Assert, ast.Raise, ast.If)) for node in ast.walk(tree)), (
        'The script does not assert or reject unsuccessful responses.'
    )

    try:
        result = subprocess.run(
            ['python3', script_path], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f'Script {script_path} exited with code {result.returncode}.\n'
            f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f'Script {script_path} timed out after 10 seconds.')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
