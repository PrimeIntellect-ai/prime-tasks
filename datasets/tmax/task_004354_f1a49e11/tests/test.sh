#!/bin/bash
mkdir -p /logs/verifier

# Stop stale copies of the stack so the submitted launcher is exercised.
pkill -f '/home/user/app/sanitizer.py' 2>/dev/null || true
pkill -f '/home/user/app/core.py' 2>/dev/null || true
pkill nginx 2>/dev/null || true
fuser -k 8080/tcp 2>/dev/null || true
fuser -k 8081/tcp 2>/dev/null || true
fuser -k 8082/tcp 2>/dev/null || true
sleep 1

cat << 'MOCK_EOF' > /tmp/verifier_core.py
import base64
import hashlib
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RECORDS = '/tmp/verifier_core_records.jsonl'
open(RECORDS, 'w').close()

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        record = {
            'method': self.command,
            'path': self.path,
            'body': base64.b64encode(body).decode('ascii'),
            'content_type': self.headers.get('Content-Type'),
        }
        with open(RECORDS, 'a') as f:
            f.write(json.dumps(record) + '\n')
            f.flush()

        status = 200
        response = b'{"applied":true,"status":"success"}\n'
        try:
            payload = json.loads(body.decode('utf-8'))
            for operation in payload:
                value = operation.get('value') if isinstance(operation, dict) else None
                if isinstance(value, dict) and 'verifier_nonce' in value and 'requested_status' in value:
                    status = int(value['requested_status'])
                    digest = hashlib.sha256(body).hexdigest().encode('ascii')
                    response = b'core-response:' + str(status).encode('ascii') + b':' + digest + b':\x00end'
                    break
        except Exception:
            status = 422
            response = b'invalid-json-from-core'

        self.send_response(status)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, fmt, *args):
        pass

ThreadingHTTPServer(('127.0.0.1', 8082), Handler).serve_forever()
MOCK_EOF

python3 /tmp/verifier_core.py >/tmp/verifier_core.log 2>&1 &
MOCK_PID=$!

# Execute the submitted stack launcher. The verifier's instrumented Core already
# owns 8082, so an attempted duplicate Core cannot replace it.
(cd /home/user/app && timeout 15s bash ./start.sh) >/tmp/submitted_start.log 2>&1 &
START_PID=$!

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import random
import re
import socket
import string
import subprocess
import time
import urllib.error
import urllib.request
import uuid
import pytest

CLEAN_CORPUS_DIR = '/home/user/corpus/clean'
EVIL_CORPUS_DIR = '/home/user/corpus/evil'
TARGET_URL = 'http://127.0.0.1:8080/api/patch'
DIRECT_SANITIZER_URL = 'http://127.0.0.1:8081/api/patch'
RECORDS = '/tmp/verifier_core_records.jsonl'


def wait_for_port(port, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.3):
                return
        except OSError:
            time.sleep(0.15)
    pytest.fail(f'port {port} did not become available')


def send_raw(url, body):
    req = urllib.request.Request(
        url,
        data=body,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except urllib.error.URLError:
        return None, b''


def send_post_request(url, payload):
    status, _ = send_raw(url, json.dumps(payload).encode('utf-8'))
    return status


def records():
    if not os.path.exists(RECORDS):
        return []
    result = []
    with open(RECORDS) as f:
        for line in f:
            if line.strip():
                result.append(json.loads(line))
    return result


def listener_inodes(port):
    wanted = f'{port:04X}'
    found = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def processes_holding(inodes):
    holders = []
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except (OSError, PermissionError):
            continue
        if not any(link.startswith('socket:[') and link[8:-1] in inodes for link in links):
            continue
        try:
            with open(f'/proc/{pid}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\x00', b' ').decode(errors='replace')
        except OSError:
            cmdline = ''
        holders.append(cmdline)
    return holders


@pytest.fixture(scope='module', autouse=True)
def stack_ready():
    for port in (8082, 8081, 8080):
        wait_for_port(port)


def test_required_artifacts_and_nginx_runtime():
    assert os.path.isfile('/home/user/app/nginx.conf'), 'nginx.conf is missing'
    assert os.path.isfile('/home/user/app/sanitizer.py'), 'sanitizer.py is missing'
    assert os.path.isfile('/home/user/app/start.sh'), 'start.sh is missing'

    checked = subprocess.run(
        ['nginx', '-T', '-c', '/home/user/app/nginx.conf'],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=5,
    )
    assert checked.returncode == 0, checked.stdout
    effective = checked.stdout
    assert re.search(r'location\s+[^\{]*?/api/\s*\{', effective), 'no /api/ Nginx location'
    assert re.search(r'proxy_pass\s+http://', effective), 'Nginx does not proxy /api traffic'
    assert '8081' in effective, 'Nginx configuration does not target the sanitizer port'

    nginx_holders = processes_holding(listener_inodes(8080))
    assert any('nginx' in command.lower() for command in nginx_holders), \
        f'port 8080 is not owned by Nginx: {nginx_holders}'
    assert listener_inodes(8081), 'nothing is listening on sanitizer port 8081'


def test_adversarial_corpus():
    # Preserve the original corpus assertions.
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]

    assert len(clean_files) > 0, 'Clean corpus is empty.'
    assert len(evil_files) > 0, 'Evil corpus is empty.'

    clean_failed = []
    evil_bypassed = []

    for filename in clean_files:
        with open(os.path.join(CLEAN_CORPUS_DIR, filename)) as f:
            payload = json.load(f)
        status = send_post_request(TARGET_URL, payload)
        if status != 200:
            clean_failed.append(f'{filename} (status: {status})')

    for filename in evil_files:
        with open(os.path.join(EVIL_CORPUS_DIR, filename)) as f:
            payload = json.load(f)
        status = send_post_request(TARGET_URL, payload)
        if status != 403:
            evil_bypassed.append(f'{filename} (status: {status})')

    errors = []
    if clean_failed:
        errors.append(f'{len(clean_failed)} of {len(clean_files)} clean modified/rejected: ' + ', '.join(clean_failed))
    if evil_bypassed:
        errors.append(f'{len(evil_bypassed)} of {len(evil_files)} evil bypassed: ' + ', '.join(evil_bypassed))
    if errors:
        pytest.fail(' | '.join(errors))


def make_dynamic_body(path, requested_status):
    nonce = uuid.uuid4().hex
    # Deliberately non-canonical formatting makes exact-body forwarding observable.
    text = '[  { "op" : "replace", "path" : ' + json.dumps(path) + \
           ', "value" : {"verifier_nonce":' + json.dumps(nonce) + \
           ',"requested_status":' + str(requested_status) + '} }  ]'
    return text.encode('utf-8')


@pytest.mark.parametrize('status', [207, 418])
def test_random_safe_requests_are_forwarded_exactly(status):
    path = '/profile_' + uuid.uuid4().hex + '/value'
    body = make_dynamic_body(path, status)
    received_status, received_body = send_raw(TARGET_URL, body)

    expected = (b'core-response:' + str(status).encode('ascii') + b':' +
                hashlib.sha256(body).hexdigest().encode('ascii') + b':\x00end')
    assert received_status == status, 'sanitizer did not preserve the Core status'
    assert received_body == expected, 'sanitizer did not preserve the Core response body'

    encoded = base64.b64encode(body).decode('ascii')
    matching = [r for r in records() if r.get('body') == encoded]
    assert matching, 'safe request never reached the Core service'
    assert matching[-1]['method'] == 'POST'
    assert matching[-1]['path'] == '/api/patch'


def test_sanitizer_is_reachable_on_8081_and_forwards():
    body = make_dynamic_body('/direct_' + uuid.uuid4().hex, 206)
    status, response = send_raw(DIRECT_SANITIZER_URL, body)
    expected = (b'core-response:206:' + hashlib.sha256(body).hexdigest().encode('ascii') + b':\x00end')
    assert status == 206
    assert response == expected


def test_random_protected_paths_are_blocked_without_core_access():
    protected = ['id', 'role', 'is_admin']
    for root in protected:
        suffixes = ['', '/' + uuid.uuid4().hex, '/0/' + uuid.uuid4().hex]
        for suffix in suffixes:
            marker = uuid.uuid4().hex
            payload = [
                {'op': 'replace', 'path': '/display_' + uuid.uuid4().hex, 'value': marker},
                {'op': random.choice(['add', 'remove', 'replace']), 'path': '/' + root + suffix, 'value': marker},
            ]
            body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
            status, _ = send_raw(TARGET_URL, body)
            assert status == 403, f'protected path /{root}{suffix} returned {status}'
            encoded = base64.b64encode(body).decode('ascii')
            assert not any(r.get('body') == encoded for r in records()), \
                'a forbidden request was forwarded to Core'


def test_similar_but_unprotected_roots_remain_safe():
    for path in ['/identity_' + uuid.uuid4().hex,
                 '/roleplay_' + uuid.uuid4().hex,
                 '/is_administered_' + uuid.uuid4().hex]:
        body = make_dynamic_body(path, 209)
        status, response = send_raw(TARGET_URL, body)
        expected = (b'core-response:209:' + hashlib.sha256(body).hexdigest().encode('ascii') + b':\x00end')
        assert status == 209
        assert response == expected
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
RC=$?

kill "$MOCK_PID" "$START_PID" 2>/dev/null || true
if [ "$RC" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
