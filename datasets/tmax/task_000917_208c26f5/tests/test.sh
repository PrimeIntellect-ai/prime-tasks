#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import pathlib
import re
import secrets
import socket
import string
import subprocess
import time
import uuid

import pytest

APP = pathlib.Path('/home/user/app')
BINARY = APP / 'filter/metric_filter'
SOURCE = APP / 'filter/main.go'


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def service_text(name):
    path = pathlib.Path('/home/user/.config/systemd/user') / name
    assert path.is_file(), f'Missing user unit: {path}'
    text = path.read_text(errors='replace')
    assert '[Service]' in text, f'{name} has no [Service] section'
    return text


def assert_listening(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(2)
        assert sock.connect_ex(('127.0.0.1', port)) == 0, f'127.0.0.1:{port} is not listening'


def test_app_mount_service():
    """Verify that the requested enabled bindfs unit owns a live source-to-target mount."""
    res = run(['systemctl', '--user', 'is-active', 'app-mount.service'])
    assert res.stdout.strip() == 'active', 'app-mount.service is not active'

    enabled = run(['systemctl', '--user', 'is-enabled', 'app-mount.service'])
    assert enabled.returncode == 0 and enabled.stdout.strip() in {'enabled', 'enabled-runtime'}, \
        'app-mount.service is not enabled'

    mountpoint = pathlib.Path('/home/user/app/config_mount')
    source = pathlib.Path('/home/user/app/config_source')
    assert os.path.ismount(mountpoint), '/home/user/app/config_mount is not mounted'

    unit = service_text('app-mount.service')
    assert re.search(r'(?m)^\s*ExecStart\s*=.*\bbindfs\b', unit), 'mount unit does not execute bindfs'
    assert '/home/user/app/config_source' in unit, 'mount unit does not use config_source'
    assert '/home/user/app/config_mount' in unit, 'mount unit does not target config_mount'
    assert re.search(r'(?m)^\s*ExecStop\s*=', unit), 'mount unit has no unmount action'

    # A random canary proves this is the requested live source mapping, not an
    # unrelated mount placed on the expected target.
    name = '.verifier-' + uuid.uuid4().hex
    source_file = source / name
    mounted_file = mountpoint / name
    payload = secrets.token_hex(32)
    try:
        source_file.write_text(payload)
        assert mounted_file.is_file(), 'config_source is not visible through config_mount'
        assert mounted_file.read_text() == payload, 'bindfs mount changed source content'
        payload2 = secrets.token_hex(32)
        mounted_file.write_text(payload2)
        assert source_file.read_text() == payload2, 'config_mount is not a writable view of config_source'
    finally:
        try:
            source_file.unlink()
        except FileNotFoundError:
            pass


def redis_command(port, *parts):
    encoded = [str(p).encode() for p in parts]
    request = b'*%d\r\n' % len(encoded)
    for part in encoded:
        request += b'$%d\r\n' % len(part) + part + b'\r\n'
    with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
        sock.sendall(request)
        f = sock.makefile('rb')
        prefix = f.read(1)
        if prefix == b'+':
            return f.readline().rstrip(b'\r\n')
        if prefix == b':':
            return int(f.readline().rstrip(b'\r\n'))
        if prefix == b'$':
            length = int(f.readline().rstrip(b'\r\n'))
            if length == -1:
                return None
            data = f.read(length)
            assert f.read(2) == b'\r\n'
            return data
        if prefix == b'-':
            raise AssertionError('Redis error: ' + f.readline().decode(errors='replace'))
        raise AssertionError(f'Invalid Redis response prefix: {prefix!r}')


def test_redis_tunnel_service():
    """Verify the active enabled service describes SSH forwarding and reaches Redis."""
    res = run(['systemctl', '--user', 'is-active', 'redis-tunnel.service'])
    assert res.stdout.strip() == 'active', 'redis-tunnel.service is not active'

    enabled = run(['systemctl', '--user', 'is-enabled', 'redis-tunnel.service'])
    assert enabled.returncode == 0 and enabled.stdout.strip() in {'enabled', 'enabled-runtime'}, \
        'redis-tunnel.service is not enabled'

    unit = service_text('redis-tunnel.service')
    compact = re.sub(r'\s+', ' ', unit)
    assert re.search(r'(?m)^\s*ExecStart\s*=.*\bssh\b', unit), 'tunnel unit does not execute ssh'
    assert re.search(r'(?:-L\s*|LocalForward\s+)(?:127\.0\.0\.1:)?9000:127\.0\.0\.1:6379', compact), \
        'tunnel unit lacks the required 9000-to-6379 local forwarding rule'
    assert re.search(r'(?:user@localhost|\blocalhost\b)', compact), 'tunnel unit does not connect to localhost'

    assert_listening(9000)

    # Exercise the endpoint as Redis with unpredictable data. Merely opening an
    # arbitrary listener on 9000 cannot satisfy this check.
    assert redis_command(9000, 'PING') == b'PONG'
    key = 'verifier:' + uuid.uuid4().hex
    value = secrets.token_hex(40)
    try:
        assert redis_command(9000, 'SET', key, value) == b'OK'
        assert redis_command(9000, 'GET', key) == value.encode()
        # Confirm the same datastore is reached at the specified tunnel target.
        assert redis_command(6379, 'GET', key) == value.encode()
    finally:
        try:
            redis_command(9000, 'DEL', key)
        except Exception:
            pass


def test_go_binary_exists():
    """Verify that the Go source and compiled executable exist at the requested paths."""
    assert SOURCE.is_file(), f'Go source {SOURCE} is missing'
    assert BINARY.is_file(), f'Go binary {BINARY} is missing'
    assert os.access(BINARY, os.X_OK), f'Go binary {BINARY} is not executable'

    rebuilt = '/tmp/metric_filter-' + uuid.uuid4().hex
    result = run(['go', 'build', '-o', rebuilt, str(SOURCE)], timeout=60)
    assert result.returncode == 0, f'main.go does not compile: {result.stderr}'
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)


def test_adversarial_corpus():
    """Retain the original shipped-corpus assertions."""
    evil_corpus_path = '/home/user/corpus/evil_metrics.jsonl'
    clean_corpus_path = '/home/user/corpus/clean_metrics.jsonl'

    assert os.path.isfile(evil_corpus_path), f'Missing evil corpus: {evil_corpus_path}'
    assert os.path.isfile(clean_corpus_path), f'Missing clean corpus: {clean_corpus_path}'

    with open(clean_corpus_path) as f:
        clean_lines = [line.strip() for line in f if line.strip()]

    clean_failed = []
    for line in clean_lines:
        res = run([str(BINARY)], input=line)
        if res.stdout.strip() != line:
            clean_failed.append(line)

    with open(evil_corpus_path) as f:
        evil_lines = [line.strip() for line in f if line.strip()]

    evil_failed = []
    for line in evil_lines:
        res = run([str(BINARY)], input=line)
        if res.stdout.strip() != '':
            evil_failed.append(line)

    errors = []
    if evil_failed:
        errors.append(f'{len(evil_failed)} of {len(evil_lines)} evil bypassed')
    if clean_failed:
        errors.append(f'{len(clean_failed)} of {len(clean_lines)} clean modified')
    if errors:
        pytest.fail(' | '.join(errors) + f'. Offending clean: {clean_failed[:3]}..., Offending evil: {evil_failed[:3]}...')


def make_line(obj):
    # Varied formatting ensures exact preservation is tested rather than JSON re-encoding.
    if secrets.randbelow(2):
        return json.dumps(obj, separators=(',', ':'), ensure_ascii=False)
    return json.dumps(obj, separators=(', ', ': '), ensure_ascii=False)


def test_randomized_filter_semantics_and_line_streaming():
    """Exercise runtime-generated clean, boundary, and malicious objects in one stream."""
    token = secrets.token_hex(12)
    clean_objects = [
        {'metric_name': 'requests_' + token, 'metric_value': 0, 'tags': []},
        {'metric_name': 'script_tag_' + token, 'metric_value': 1.25, 'tags': ['x' * 50]},
        {'metric_name': 'DROP-TABLE-' + token, 'metric_value': 999, 'tags': ['region=' + token]},
        {'other': token, 'metric_name': 'latency_' + token, 'tags': ['a', 'b']},
    ]
    evil_objects = [
        {'metric_name': 'negative_' + token, 'metric_value': -1, 'tags': []},
        {'metric_name': 'tiny_' + token, 'metric_value': -0.000001, 'tags': ['ok']},
        {'metric_name': token + 'DROP_TABLE' + secrets.token_hex(4), 'metric_value': 5, 'tags': []},
        {'metric_name': secrets.token_hex(4) + 'SCRIPT_TAG' + token, 'metric_value': 5, 'tags': []},
        {'metric_name': 'longtag_' + token, 'metric_value': 5, 'tags': ['z' * 51]},
        {'metric_name': 'later_' + token, 'metric_value': 5, 'tags': ['ok', token + ('q' * 51)]},
    ]

    # Add more unpredictable clean values so a fixed allowlist cannot pass.
    alphabet = string.ascii_letters + string.digits
    for _ in range(12):
        name = 'm_' + ''.join(secrets.choice(alphabet) for _ in range(24))
        clean_objects.append({'metric_name': name, 'metric_value': secrets.randbelow(100000) / 10, 'tags': [token]})

    records = [(make_line(o), True) for o in clean_objects] + [(make_line(o), False) for o in evil_objects]
    # Shuffle without relying on a fixed test order.
    for i in range(len(records) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        records[i], records[j] = records[j], records[i]

    input_data = ''.join(line + '\n' for line, _ in records)
    expected = ''.join(line + '\n' for line, clean in records if clean)

    rebuilt = '/tmp/rebuilt-filter-' + uuid.uuid4().hex
    build = run(['go', 'build', '-o', rebuilt, str(SOURCE)], timeout=60)
    assert build.returncode == 0, f'main.go does not compile: {build.stderr}'

    for executable in (str(BINARY), rebuilt):
        result = run([executable], input=input_data, timeout=10)
        assert result.returncode == 0, f'{executable} exited with {result.returncode}: {result.stderr}'
        assert result.stdout == expected, 'filter did not preserve exactly the clean lines and omit all malicious lines'


def http_get(port, path):
    conn = http.client.HTTPConnection('127.0.0.1', port, timeout=4)
    try:
        conn.request('GET', path, headers={'Host': 'localhost', 'Accept-Encoding': 'identity'})
        response = conn.getresponse()
        return response.status, response.read()
    finally:
        conn.close()


def test_stack_startup_and_gateway_to_flask_path():
    """Run the supplied starter, require the stack, and verify Nginx proxies to Flask."""
    starter = APP / 'start_services.sh'
    assert starter.is_file(), 'start_services.sh is missing'
    assert os.access(starter, os.X_OK), 'start_services.sh is not executable'
    started = run(['sudo', '-u', 'user', 'env', 'HOME=/home/user', str(starter)], timeout=30)
    assert started.returncode == 0, f'start_services.sh failed: {started.stderr}'

    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            for port in (8080, 5000, 6379):
                assert_listening(port)
            break
        except AssertionError:
            time.sleep(0.25)
    for port in (8080, 5000, 6379):
        assert_listening(port)

    nginx_files = []
    for root, _, files in os.walk('/etc/nginx'):
        for filename in files:
            path = os.path.join(root, filename)
            try:
                nginx_files.append(open(path, errors='replace').read())
            except OSError:
                pass
    nginx_config = '\n'.join(nginx_files)
    assert re.search(r'listen\s+(?:127\.0\.0\.1:)?8080\b', nginx_config), 'Nginx is not configured for port 8080'
    assert re.search(r'proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000\b', nginx_config), \
        'Nginx is not configured to proxy to the Flask aggregator on port 5000'

    # A random route should produce the same upstream response directly and via
    # Nginx. This proves the listener is a functioning proxy rather than an
    # unrelated process merely occupying port 8080.
    path = '/verifier-' + uuid.uuid4().hex
    direct_status, direct_body = http_get(5000, path)
    gateway_status, gateway_body = http_get(8080, path)
    assert gateway_status not in (502, 503, 504), 'Nginx cannot reach Flask'
    assert (gateway_status, gateway_body) == (direct_status, direct_body), \
        'Nginx response does not match the Flask upstream response'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
