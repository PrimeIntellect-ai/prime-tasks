#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import re
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

APP = Path('/home/user/app')
OLD_HASH_FILE = APP / 'legacy_hash.txt'
CPP_FILE = APP / 'recover_pin.cpp'
BIN_FILE = APP / 'recover_pin'
REDIS_CONF = APP / 'redis/redis.conf'
FLASK_ENV = APP / 'flask/.env'
NGINX_CONF = APP / 'nginx/nginx.conf'
REPORT_FILE = APP / 'rotation_report.txt'


def recover_expected_pin():
    target = OLD_HASH_FILE.read_text().strip().lower()
    assert re.fullmatch(r'[0-9a-f]{64}', target), 'legacy_hash.txt must contain a SHA-256 hex digest'
    for i in range(1_000_000):
        pin = f'{i:06d}'
        if hashlib.sha256(pin.encode()).hexdigest() == target:
            return pin
    pytest.fail('Legacy hash does not correspond to a six-digit PIN')


@pytest.fixture(scope='session')
def old_pin():
    return recover_expected_pin()


@pytest.fixture(scope='session')
def compiled_tool():
    assert CPP_FILE.is_file(), f'Missing C++ source file: {CPP_FILE}'
    compile_proc = subprocess.run(
        ['g++', '-O3', str(CPP_FILE), '-o', str(BIN_FILE)],
        capture_output=True,
        timeout=60,
    )
    assert compile_proc.returncode == 0, f'Compilation failed:\n{compile_proc.stderr.decode(errors="replace")}'
    assert BIN_FILE.is_file() and os.access(BIN_FILE, os.X_OK), 'Compiled recovery tool is missing or not executable'
    return str(BIN_FILE)


def run_tool(binary, pin, timeout):
    digest = hashlib.sha256(pin.encode()).hexdigest()
    proc = subprocess.run([binary], input=(digest + '\n').encode(), capture_output=True, timeout=timeout)
    assert proc.returncode == 0, f'Executable failed for hash {digest} with return code {proc.returncode}'
    try:
        output = proc.stdout.decode('ascii').strip()
    except UnicodeDecodeError:
        pytest.fail('Recovery tool emitted non-ASCII output')
    assert output == pin, f'Incorrect output for hash {digest}: expected {pin!r}, got {output!r}'
    assert re.fullmatch(rb'\s*' + pin.encode() + rb'\s*', proc.stdout), 'stdout must contain only the recovered PIN'


def test_cpp_tool_performance_and_general_recovery(compiled_tool, old_pin):
    # Retain the original fast fixed-batch assertion.
    start = time.perf_counter()
    for i in range(100):
        run_tool(compiled_tool, f'{i:06d}', 3)
    elapsed = time.perf_counter() - start
    assert elapsed <= 0.5, f'Performance failed on the original batch: {elapsed:.4f}s > 0.5s'

    # Exercise unpredictable PINs across the complete six-digit domain.
    selected = {old_pin}
    while len(selected) < 10:
        selected.add(f'{secrets.randbelow(999900) + 100:06d}')
    start = time.perf_counter()
    for pin in selected:
        run_tool(compiled_tool, pin, 10)
    elapsed = time.perf_counter() - start
    assert elapsed <= 45, f'General recovery batch was too slow: {elapsed:.4f}s > 45s'


def parse_rotated_passwords():
    assert REDIS_CONF.is_file(), f'Missing Redis config: {REDIS_CONF}'
    assert FLASK_ENV.is_file(), f'Missing Flask environment file: {FLASK_ENV}'

    redis_text = REDIS_CONF.read_text()
    active_requirepass = [
        line for line in redis_text.splitlines()
        if re.match(r'^\s*requirepass(?:\s|$)', line) and not re.match(r'^\s*#', line)
    ]
    assert len(active_requirepass) == 1, 'Redis config must have exactly one active requirepass directive'
    redis_match = re.fullmatch(r'\s*requirepass\s+([A-Za-z0-9]{16})\s*(?:#.*)?', active_requirepass[0])
    assert redis_match, 'Redis requirepass must be exactly 16 alphanumeric characters'
    redis_password = redis_match.group(1)

    env_text = FLASK_ENV.read_text()
    active_passwords = [
        line for line in env_text.splitlines()
        if re.match(r'^\s*REDIS_PASSWORD\s*=', line) and not re.match(r'^\s*#', line)
    ]
    assert len(active_passwords) == 1, 'Flask .env must have exactly one active REDIS_PASSWORD assignment'
    env_match = re.fullmatch(r'\s*REDIS_PASSWORD\s*=\s*([A-Za-z0-9]{16})\s*', active_passwords[0])
    assert env_match, 'Flask REDIS_PASSWORD must be exactly 16 alphanumeric characters'
    flask_password = env_match.group(1)

    assert redis_password == flask_password, 'Redis and Flask must use the same rotated password'
    return redis_password


def test_rotation_configuration_and_report(old_pin):
    new_password = parse_rotated_passwords()
    assert new_password != old_pin, 'The rotated password must differ from the legacy PIN'

    assert REPORT_FILE.is_file(), f'Missing rotation report: {REPORT_FILE}'
    lines = REPORT_FILE.read_text().splitlines()
    assert len(lines) >= 2, 'Rotation report must contain at least two lines'
    assert lines[0].strip() == old_pin, 'Line 1 of the rotation report must contain the recovered legacy PIN'
    assert lines[1].strip() == new_password, 'Line 2 of the rotation report must contain the configured new password'


def drop_to_nobody():
    entry = pwd.getpwnam('nobody')
    os.setgroups([])
    os.setgid(entry.pw_gid)
    os.setuid(entry.pw_uid)


def wait_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail(f'Service did not begin listening on port {port}')


def redis_command(port, *parts):
    payload = f'*{len(parts)}\r\n'.encode()
    for part in parts:
        data = str(part).encode()
        payload += f'${len(data)}\r\n'.encode() + data + b'\r\n'
    with socket.create_connection(('127.0.0.1', port), timeout=2) as sock:
        sock.sendall(payload)
        return sock.recv(4096)


def http_get(url):
    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            return response.status, response.read().decode(errors='replace')
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode(errors='replace')


def test_services_restart_and_nginx_policy(old_pin):
    new_password = parse_rotated_passwords()
    assert NGINX_CONF.is_file(), f'Missing Nginx config: {NGINX_CONF}'

    subprocess.run(['fuser', '-k', '5000/tcp', '8000/tcp', '8080/tcp', '8081/tcp', '16379/tcp'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    with tempfile.TemporaryDirectory(prefix='rotation_verify_') as root:
        root_path = Path(root)
        os.chmod(root, 0o755)
        nobody = pwd.getpwnam('nobody')
        os.chown(root, nobody.pw_uid, nobody.pw_gid)

        server_script = root_path / 'fixture_services.py'
        api_token = 'API_' + secrets.token_hex(16)
        auth_token = 'AUTH_' + secrets.token_hex(16)
        debug_token = 'DEBUG_' + secrets.token_hex(16)
        server_script.write_text(r'''
import http.server, os, socket, sys, threading
kind, token = sys.argv[1], sys.argv[2]
port = int(sys.argv[3])
password = sys.argv[4] if len(sys.argv) > 4 else ''
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if kind == 'api':
            def cmd(*parts):
                payload = ('*%d\r\n' % len(parts)).encode()
                for part in parts:
                    data = part.encode()
                    payload += ('$%d\r\n' % len(data)).encode() + data + b'\r\n'
                with socket.create_connection(('127.0.0.1', 16379), timeout=2) as s:
                    s.sendall(payload)
                    return s.recv(1024)
            if not cmd('AUTH', password).startswith(b'+OK') or not cmd('AUTH', password, 'PING').endswith(b'+PONG\r\n'):
                self.send_response(503); self.end_headers(); return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(token.encode())
    def log_message(self, *args): pass
http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
''')
        os.chown(server_script, nobody.pw_uid, nobody.pw_gid)

        processes = []
        try:
            redis_proc = subprocess.Popen(
                ['redis-server', str(REDIS_CONF), '--port', '16379', '--bind', '127.0.0.1',
                 '--daemonize', 'no', '--pidfile', str(root_path / 'redis.pid'), '--dir', root,
                 '--logfile', ''],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, preexec_fn=drop_to_nobody,
            )
            processes.append(redis_proc)
            wait_port(16379)
            assert redis_command(16379, 'PING').startswith(b'-NOAUTH'), 'Redis must reject unauthenticated access'
            assert redis_command(16379, 'AUTH', old_pin).startswith(b'-'), 'Redis still accepts the legacy PIN'
            assert redis_command(16379, 'AUTH', new_password).startswith(b'+OK'), 'Redis rejects the rotated password'

            for kind, token, port, password in [
                ('api', api_token, 5000, new_password),
                ('auth', auth_token, 8000, ''),
                ('debug', debug_token, 8081, ''),
            ]:
                proc = subprocess.Popen(
                    ['python3', str(server_script), kind, token, str(port), password],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=drop_to_nobody,
                )
                processes.append(proc)
                wait_port(port)

            nginx_proc = subprocess.Popen(
                ['nginx', '-p', root + '/', '-c', str(NGINX_CONF),
                 '-g', f'daemon off; pid {root}/nginx.pid; error_log stderr;'],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, preexec_fn=drop_to_nobody,
            )
            processes.append(nginx_proc)
            wait_port(8080)

            status, body = http_get('http://127.0.0.1:8080/api/probe')
            assert status == 200 and body == api_token, '/api/ must proxy to the Flask backend, which must authenticate to Redis'

            status, body = http_get('http://127.0.0.1:8080/auth/probe')
            assert status == 200 and body == auth_token, '/auth/ must proxy to the Authentication Daemon'

            status, body = http_get('http://127.0.0.1:8080/auth-debug/probe')
            assert status == 403, '/auth-debug/ must explicitly return HTTP 403'
            assert debug_token not in body, '/auth-debug/ was proxied to the debug service instead of being blocked'
        finally:
            for proc in reversed(processes):
                if proc.poll() is None:
                    proc.terminate()
            for proc in reversed(processes):
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
