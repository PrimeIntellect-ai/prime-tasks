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
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import signal
import socket
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests


def b64url(value):
    return base64.urlsafe_b64encode(value).decode('ascii').rstrip('=')


def make_jwt(algorithm, user, signature='dummysignature', extra_header=None):
    header = {'alg': algorithm}
    if extra_header:
        header.update(extra_header)
    return '%s.%s.%s' % (
        b64url(json.dumps(header, separators=(',', ':')).encode()),
        b64url(json.dumps({'user': user}, separators=(',', ':')).encode()),
        signature,
    )


def decode_base64url(data):
    return base64.urlsafe_b64decode(data + ('=' * (-len(data) % 4))).decode('utf-8')


def listening_pids(port):
    inodes = set()
    wanted = format(port, '04X')
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == '0A' and fields[1].rsplit(':', 1)[1].upper() == wanted:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = '/proc/%s/fd' % name
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def stop_listeners(port):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listening_pids(port)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.35)


def wait_for_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.05)
    return False


def test_admin_exploit_jwt_file():
    jwt_path = '/home/user/admin_exploit.jwt'
    assert os.path.exists(jwt_path), f'Exploit file not found at {jwt_path}'
    assert stat.S_ISREG(os.stat(jwt_path).st_mode), f'{jwt_path} must be a regular file'
    perms = stat.S_IMODE(os.stat(jwt_path).st_mode)
    assert perms == 0o600, f'Permissions for {jwt_path} must be 0600, found {oct(perms)}'

    with open(jwt_path, 'r') as f:
        jwt_content = f.read().strip()
    parts = jwt_content.split('.')
    assert len(parts) in (2, 3), 'JWT must have at least a header and payload separated by dots'
    try:
        header = json.loads(decode_base64url(parts[0]))
        payload = json.loads(decode_base64url(parts[1]))
    except Exception as exc:
        pytest.fail(f'Failed to decode JWT header/payload: {exc}')
    assert header.get('alg', '').lower() == 'none', "JWT header must specify 'alg': 'none'"
    assert payload.get('user') == 'admin', "JWT payload must specify 'user': 'admin'"


def test_proxy_artifact_and_dynamic_forwarding():
    proxy_path = '/home/user/sec_proxy.py'
    assert os.path.exists(proxy_path), f'Proxy source not found at {proxy_path}'
    assert stat.S_ISREG(os.stat(proxy_path).st_mode), f'{proxy_path} must be a regular file'
    with open(proxy_path, 'rb') as f:
        source = f.read()
    assert source, f'{proxy_path} is empty'
    try:
        compile(source, proxy_path, 'exec')
    except Exception as exc:
        pytest.fail(f'{proxy_path} is not valid executable Python: {exc}')

    stop_listeners(8080)
    stop_listeners(9000)
    audit_path = '/home/user/security_audit.log'
    try:
        os.unlink(audit_path)
    except FileNotFoundError:
        pass

    origin_nonce = secrets.token_hex(24)
    path_nonce = secrets.token_urlsafe(15)
    records = []
    records_lock = threading.Lock()

    class OriginHandler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.0'

        def log_message(self, *args):
            pass

        def handle_request(self):
            length = int(self.headers.get('Content-Length', '0') or '0')
            body = self.rfile.read(length) if length else b''
            record = {
                'method': self.command,
                'path': self.path,
                'body': body,
                'authorization': self.headers.get('Authorization'),
            }
            with records_lock:
                records.append(record)

            if self.path.startswith('/opaque-' + path_nonce):
                response = ('opaque-origin:' + origin_nonce).encode() + b'\x00tail'
                self.send_response(206)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('X-Origin-Nonce', origin_nonce)
                self.send_header('Content-Length', str(len(response)))
                self.end_headers()
                self.wfile.write(response)
                return

            user = 'unknown'
            auth = self.headers.get('Authorization', '')
            if auth.startswith('Bearer '):
                try:
                    token_parts = auth[7:].split('.')
                    user = json.loads(decode_base64url(token_parts[1])).get('user', 'unknown')
                except Exception:
                    pass
            response_obj = {
                'user': user,
                'ssn': '731-42-9876',
                'role': 'user',
                'origin_nonce': origin_nonce,
                'method': self.command,
                'path': self.path,
                'body': body.decode('utf-8', errors='replace'),
            }
            response = json.dumps(response_obj).encode()
            status = 200 if self.path == '/profile' else 207
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('X-Origin-Nonce', origin_nonce)
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response)

    for method in ('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'):
        setattr(OriginHandler, 'do_' + method, OriginHandler.handle_request)

    origin = ThreadingHTTPServer(('127.0.0.1', 9000), OriginHandler)
    origin_thread = threading.Thread(target=origin.serve_forever, daemon=True)
    origin_thread.start()
    proxy_proc = None

    try:
        proxy_proc = subprocess.Popen(
            ['python3', proxy_path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd='/home/user',
        )
        assert wait_for_port(8080), 'Executing sec_proxy.py did not start a proxy on 127.0.0.1:8080'

        # Preserve the original fixed alg:none assertion.
        fixed_none = make_jwt('none', 'test', signature='')
        fixed_reject_path = '/profile'
        response = requests.get(
            'http://127.0.0.1:8080' + fixed_reject_path,
            headers={'Authorization': 'Bearer ' + fixed_none},
            timeout=3,
        )
        assert response.status_code == 403, f'Expected HTTP 403 for alg:none JWT, got {response.status_code}'

        # Exercise case-insensitive rejection on unpredictable paths and methods.
        rejected_paths = [fixed_reject_path]
        for index, algorithm in enumerate(('NoNe', 'NONE', 'nOnE')):
            path = f'/reject-{path_nonce}-{index}?v={secrets.token_hex(4)}'
            rejected_paths.append(path)
            token = make_jwt(algorithm, 'blocked-' + secrets.token_hex(4), signature='ignored',
                             extra_header={'typ': 'JWT', 'kid': secrets.token_hex(5)})
            response = requests.request(
                ('POST', 'PATCH', 'DELETE')[index],
                'http://127.0.0.1:8080' + path,
                headers={'Authorization': 'Bearer ' + token},
                data=('rejected-body-' + secrets.token_hex(6)).encode(),
                timeout=3,
            )
            assert response.status_code == 403, (
                f'Expected HTTP 403 for case variation {algorithm!r}, got {response.status_code}'
            )

        # Preserve the original allowed HS256 /profile and redaction assertions,
        # while requiring a response value known only to the live origin.
        fixed_valid = make_jwt('HS256', 'test')
        response = requests.get(
            'http://127.0.0.1:8080/profile',
            headers={'Authorization': 'Bearer ' + fixed_valid},
            timeout=3,
        )
        assert response.status_code == 200, f'Expected HTTP 200 for valid JWT, got {response.status_code}'
        try:
            data = response.json()
        except ValueError:
            pytest.fail('Response from proxy was not valid JSON')
        assert 'ssn' in data, "Response JSON did not contain 'ssn' key"
        assert data['ssn'] == '***-**-****', f"SSN was not properly redacted. Got: {data['ssn']}"
        assert data['origin_nonce'] == origin_nonce, 'Response was not obtained from the live legacy endpoint'
        assert data['user'] == 'test'

        # Verify arbitrary method, path, query, body, and a different allowed JWT algorithm.
        dynamic_path = f'/resource-{path_nonce}/child?q={secrets.token_hex(5)}'
        dynamic_body = 'body-' + secrets.token_hex(18)
        dynamic_user = 'user-' + secrets.token_hex(10)
        dynamic_token = make_jwt('RS256', dynamic_user, signature=secrets.token_urlsafe(20))
        response = requests.patch(
            'http://127.0.0.1:8080' + dynamic_path,
            headers={'Authorization': 'Bearer ' + dynamic_token, 'Content-Type': 'text/plain'},
            data=dynamic_body.encode(),
            timeout=3,
        )
        assert response.status_code == 207, f'Proxy did not preserve origin status; got {response.status_code}'
        assert response.headers.get('X-Origin-Nonce') == origin_nonce
        data = response.json()
        assert data['origin_nonce'] == origin_nonce
        assert data['method'] == 'PATCH'
        assert data['path'] == dynamic_path
        assert data['body'] == dynamic_body
        assert data['user'] == dynamic_user
        assert data['ssn'] == '***-**-****'

        # A non-JSON response must also actually be forwarded and remain intact.
        opaque_path = '/opaque-' + path_nonce + '?x=' + secrets.token_hex(5)
        response = requests.get(
            'http://127.0.0.1:8080' + opaque_path,
            headers={'Authorization': 'Bearer ' + make_jwt('ES256', 'opaque-user')},
            timeout=3,
        )
        assert response.status_code == 206
        assert response.headers.get('X-Origin-Nonce') == origin_nonce
        assert response.content == ('opaque-origin:' + origin_nonce).encode() + b'\x00tail'

        # Rejected requests must never have reached the origin.
        time.sleep(0.15)
        with records_lock:
            received_paths = [item['path'] for item in records]
            received_records = list(records)
        for path in rejected_paths:
            assert path not in received_paths, f'Rejected request {path!r} was forwarded to the legacy service'
        assert any(item['method'] == 'PATCH' and item['path'] == dynamic_path and
                   item['body'] == dynamic_body.encode() for item in received_records), (
            'The arbitrary PATCH request was not forwarded to the legacy service'
        )
        assert opaque_path in received_paths, 'The arbitrary non-JSON request was not forwarded'

        # The log was removed immediately before launching the submitted artifact,
        # so these entries cannot have been prewritten.
        assert os.path.exists(audit_path), f'Audit log not found at {audit_path}'
        perms = stat.S_IMODE(os.stat(audit_path).st_mode)
        assert perms == 0o600, f'Permissions for {audit_path} must be 0600, found {oct(perms)}'
        with open(audit_path, 'r') as f:
            lines = f.read().splitlines()
        expected_log = '[REJECTED] IP:127.0.0.1 REASON:Insecure_JWT'
        assert len(lines) == len(rejected_paths), (
            f'Every rejected request must produce exactly one audit entry; got {len(lines)} for '
            f'{len(rejected_paths)} rejections'
        )
        assert all(line == expected_log for line in lines), (
            f"Audit log entries must exactly equal '{expected_log}', got: {lines!r}"
        )
    finally:
        origin.shutdown()
        origin.server_close()
        if proxy_proc is not None and proxy_proc.poll() is None:
            proxy_proc.terminate()
            try:
                proxy_proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proxy_proc.kill()
        stop_listeners(8080)
        stop_listeners(9000)
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
