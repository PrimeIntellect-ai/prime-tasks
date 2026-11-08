#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import http.client
import json
import os
import random
import signal
import socket
import stat
import string
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')


def jwt(header, payload, secret=None, signature=None):
    h = b64url(json.dumps(header, separators=(',', ':')).encode())
    p = b64url(json.dumps(payload, separators=(',', ':')).encode())
    message = h + '.' + p
    if secret is not None:
        raw = hmac.new(secret.encode(), message.encode(), hashlib.sha256).digest()
        signature = b64url(raw)
    if signature is None:
        signature = ''
    return message + '.' + signature


def request(method, path, token=None, body=b'', extra_headers=None):
    headers = dict(extra_headers or {})
    if token is not None:
        headers['Authorization'] = 'Bearer ' + token
    conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=5)
    try:
        conn.request(method, path, body=body, headers=headers)
        response = conn.getresponse()
        return response.status, response.read()
    finally:
        conn.close()


def listener_entries(port):
    result = []
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            address, port_hex = local.rsplit(':', 1)
            if state == '0A' and int(port_hex, 16) == port:
                result.append((inode, address, table))
    return result


def listener_pids(port):
    inodes = {entry[0] for entry in listener_entries(port)}
    pids = set()
    if not inodes:
        return pids
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = '/proc/' + name + '/fd'
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd_dir + '/' + fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
                break
    return pids


def stop_listener(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_entries(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_entries(port) and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_entries(port), 'Could not free listener port %d' % port


def wait_for_port(port, process=None):
    deadline = time.time() + 8
    while time.time() < deadline:
        if process is not None and process.poll() is not None:
            raise AssertionError('Process exited before listening on port %d' % port)
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError('Timed out waiting for port %d' % port)


def phrase_count():
    path = '/app/blocked_reqs.log'
    assert os.path.lexists(path), 'Log file does not exist after a blocked request'
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), 'Blocked request log is not a regular file'
    assert not stat.S_ISLNK(st.st_mode), 'Blocked request log must not be a symlink'
    assert stat.S_IMODE(st.st_mode) == 0o600, 'Expected log permissions 0600, got %s' % oct(stat.S_IMODE(st.st_mode))
    with open(path, 'r', errors='replace') as f:
        content = f.read()
    assert 'Blocked JWT attempt' in content, 'Log lacks required text'
    return content.count('Blocked JWT attempt')


def blocked(token, expected_before):
    status, _ = request('GET', '/data', token)
    assert status == 401, 'Expected 401 for invalid JWT, got %d' % status
    deadline = time.time() + 2
    while time.time() < deadline:
        try:
            count = phrase_count()
            if count > expected_before:
                return count
        except AssertionError:
            pass
        time.sleep(0.05)
    count = phrase_count()
    assert count > expected_before, 'Blocked request did not append a log entry'
    return count


source = '/app/proxy.go'
st = os.lstat(source)
assert stat.S_ISREG(st.st_mode) and not stat.S_ISLNK(st.st_mode), '/app/proxy.go must be a regular Go source file'
with open(source, 'rb') as f:
    assert b'package main' in f.read(), '/app/proxy.go is not a Go main source file'

# The required legacy binary must initially be the process serving its discovered port.
legacy_pids = listener_pids(13337)
assert legacy_pids, '/app/legacy_api is not listening on its backend port'
assert any(os.path.realpath('/proc/%d/exe' % p) == '/app/legacy_api' for p in legacy_pids), 'The backend listener is not /app/legacy_api'

build = subprocess.run(
    ['go', 'build', '-o', '/tmp/verified_proxy', source],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90,
    env=dict(os.environ, GO111MODULE='off'))
assert build.returncode == 0, 'proxy.go did not compile:\n' + build.stdout.decode(errors='replace')

stop_listener(8080)
try:
    os.unlink('/app/blocked_reqs.log')
except FileNotFoundError:
    pass
proxy = subprocess.Popen(['/tmp/verified_proxy'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
wait_for_port(8080, proxy)
entries = listener_entries(8080)
assert entries and all(e[1].upper() == '0100007F' for e in entries), 'Proxy must listen specifically on 127.0.0.1:8080'

# Retain the original fixed checks against the real legacy backend.
valid_fixed = jwt({'alg': 'HS256', 'typ': 'JWT'}, {'user': 'admin'}, 'proxy-secret-2024')
status, _ = request('GET', '/data', valid_fixed)
assert status == 200, 'Expected 200 for the original valid JWT, got %d' % status

count = 0
none_fixed = jwt({'alg': 'none', 'typ': 'JWT'}, {'user': 'admin'})
count = blocked(none_fixed, count)
none_upper_fixed = jwt({'alg': 'NONE', 'typ': 'JWT'}, {'user': 'admin'})
count = blocked(none_upper_fixed, count)

# Replace the backend temporarily with a verifier-controlled endpoint. Its response,
# path, body, and nonce are unpredictable to the submitted proxy.
stop_listener(13337)
backend_killed = True
nonce = ''.join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(32))
expected_path = '/verify/' + nonce + '?q=' + nonce[::-1]
expected_body = ('payload-' + nonce).encode()
response_body = ('backend-proof-' + nonce).encode()
captures = []

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        captures.append((self.path, body, self.headers.get('X-Admin-Key'), self.headers.get('X-Verify-Nonce')))
        if (self.path == expected_path and body == expected_body and
                self.headers.get('X-Admin-Key') == 'SUP3R_S3CR3T_K3Y_9921' and
                self.headers.get('X-Verify-Nonce') == nonce):
            self.send_response(207)
            self.end_headers()
            self.wfile.write(response_body)
        else:
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b'bad forwarding')
    def log_message(self, fmt, *args):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 13337), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    dynamic_valid = jwt({'typ': 'JWT', 'alg': 'HS256'}, {'nonce': nonce, 'role': 'admin'}, 'proxy-secret-2024')
    status, body = request('POST', expected_path, dynamic_valid, expected_body, {'X-Verify-Nonce': nonce})
    assert status == 207, 'Valid randomized JWT was not forwarded to the controlled backend'
    assert body == response_body, 'Proxy did not return the controlled backend response'
    assert captures, 'Controlled backend received no request'
    assert captures[-1][2] == 'SUP3R_S3CR3T_K3Y_9921', 'Exact X-Admin-Key was not injected'

    # Randomized invalid cases prevent a fixed token/status lookup from passing.
    wrong_secret = 'wrong-' + nonce
    count = blocked(jwt({'alg': 'HS256'}, {'nonce': nonce}, wrong_secret), count)
    tampered = dynamic_valid.rsplit('.', 1)[0] + '.' + b64url(os.urandom(32))
    count = blocked(tampered, count)
    mixed_none = ''.join(c.upper() if random.getrandbits(1) else c for c in 'none')
    count = blocked(jwt({'alg': mixed_none}, {'nonce': nonce}), count)
    count = blocked(jwt({'typ': 'JWT'}, {'nonce': nonce}), count)
    count = blocked('not-a-jwt-' + nonce, count)
finally:
    server.shutdown()
    server.server_close()
    stop_listener(13337)
    subprocess.Popen(['/app/legacy_api'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_port(13337)

assert proxy.poll() is None, 'Compiled proxy stopped running during verification'
PY

python3 /tmp/test_final_state.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
