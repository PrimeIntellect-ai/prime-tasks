#!/bin/bash
set +e
mkdir -p /logs/verifier

cat > /tmp/kill_test_ports.py <<'PY'
import os, signal, time
ports = {8000, 8080, 8081}
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[3] == '0A' and int(fields[1].rsplit(':', 1)[1], 16) in ports:
                    inodes.add(fields[9])
    except OSError:
        pass
victims = set()
for name in os.listdir('/proc'):
    if not name.isdigit() or int(name) == os.getpid():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                victims.add(int(name))
                break
    except OSError:
        pass
for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
time.sleep(0.5)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
PY
python3 /tmp/kill_test_ports.py >/dev/null 2>&1

SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
CAPTURE=/tmp/backend-captures.log
: > "$CAPTURE"
cat > /tmp/verifier_backend.py <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import base64, hashlib, os, sys

secret, capture = sys.argv[1], sys.argv[2]
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        raw = self.rfile.read(length)
        with open(capture, 'ab', buffering=0) as f:
            f.write(base64.b64encode(raw) + b'\n')
        body = ('BACKEND:' + secret + ':' + hashlib.sha256(raw).hexdigest()).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
ThreadingHTTPServer(('127.0.0.1', 8081), Handler).serve_forever()
PY
python3 /tmp/verifier_backend.py "$SECRET" "$CAPTURE" >/tmp/verifier-backend.log 2>&1 &
BACKEND_PID=$!

if [ -f /home/user/waf.py ]; then
    python3 /home/user/waf.py >/tmp/verifier-waf.log 2>&1 &
    WAF_PID=$!
else
    WAF_PID=0
fi

if [ -f /home/user/nginx.conf ]; then
    nginx -c /home/user/nginx.conf >/tmp/verifier-nginx.log 2>&1 &
    NGINX_LAUNCH_PID=$!
else
    NGINX_LAUNCH_PID=0
fi

export VERIFIER_SECRET="$SECRET"
export VERIFIER_CAPTURE="$CAPTURE"
export VERIFIER_WAF_PID="$WAF_PID"
sleep 2

cat > /tmp/test_final_state.py <<'PY'
import ast
import hashlib
import json
import os
import random
import secrets
import socket
import string
import subprocess
import time
import urllib.error
import urllib.request

URL = 'http://127.0.0.1:8000/build'
SECRET = os.environ['VERIFIER_SECRET']
CAPTURE = os.environ['VERIFIER_CAPTURE']


def send(raw):
    req = urllib.request.Request(URL, data=raw,
        headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def expected_backend_body(raw):
    return ('BACKEND:' + SECRET + ':' + hashlib.sha256(raw).hexdigest()).encode()


def capture_count():
    try:
        with open(CAPTURE, 'rb') as f:
            return sum(1 for line in f if line.strip())
    except FileNotFoundError:
        return 0


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == '0A' and int(fields[1].rsplit(':', 1)[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass
    result = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            for fd in os.listdir(f'/proc/{name}/fd'):
                target = os.readlink(f'/proc/{name}/fd/{fd}')
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except OSError:
            pass
    return result


def cmdline(pid):
    try:
        return open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def test_required_artifacts_and_topology():
    assert os.path.isfile('/home/user/waf.py'), 'Missing /home/user/waf.py'
    assert os.path.isfile('/home/user/nginx.conf'), 'Missing /home/user/nginx.conf'
    compiled = subprocess.run(['python3', '-m', 'py_compile', '/home/user/waf.py'],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert compiled.returncode == 0, compiled.stderr.decode()
    checked = subprocess.run(['nginx', '-t', '-c', '/home/user/nginx.conf'],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert checked.returncode == 0, checked.stderr.decode()
    p8000 = listener_pids(8000)
    p8080 = listener_pids(8080)
    assert p8000, 'Nothing is listening on port 8000'
    assert p8080, 'Nothing is listening on port 8080'
    assert any('nginx' in cmdline(pid).lower() for pid in p8000), 'Port 8000 is not served by Nginx'
    assert any('/home/user/waf.py' in cmdline(pid) for pid in p8080), 'The submitted WAF is not listening on port 8080'


def test_clean_corpus():
    clean_dir = '/app/corpus/clean'
    assert os.path.isdir(clean_dir), f'Directory {clean_dir} does not exist'
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]
    assert len(clean_files) > 0, 'No clean corpus files found'
    failed = []
    for filename in clean_files:
        with open(os.path.join(clean_dir, filename), 'rb') as f:
            raw = f.read()
        try:
            status, body = send(raw)
            if status != 200:
                failed.append(f'{filename} (status {status})')
            elif body != expected_backend_body(raw):
                failed.append(f'{filename} (response was not returned by backend)')
        except Exception as e:
            failed.append(f'{filename} (Exception {e})')
    assert not failed, f"{len(failed)} of {len(clean_files)} clean modified/blocked: {', '.join(failed)}"


def test_evil_corpus():
    evil_dir = '/app/corpus/evil'
    assert os.path.isdir(evil_dir), f'Directory {evil_dir} does not exist'
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]
    assert len(evil_files) > 0, 'No evil corpus files found'
    before = capture_count()
    failed = []
    for filename in evil_files:
        with open(os.path.join(evil_dir, filename), 'rb') as f:
            raw = f.read()
        try:
            status, _ = send(raw)
            if status != 403:
                failed.append(f'{filename} (status {status})')
        except Exception as e:
            failed.append(f'{filename} (Exception {e})')
    time.sleep(0.2)
    assert capture_count() == before, 'An evil corpus request reached the backend'
    assert not failed, f"{len(failed)} of {len(evil_files)} evil bypassed: {', '.join(failed)}"


def safe_patch(token):
    return (f'--- a/src/{token}..txt\n'
            f'+++ b/src/{token}..txt\n'
            '@@ -1 +1 @@\n-old\n+new\n')


def encode_payload(expression, patch, token):
    # Deliberately noncanonical formatting verifies that the original JSON bytes
    # are forwarded rather than a verifier-known canned request.
    return ('{\n  "patch" : ' + json.dumps(patch) + ',\n'
            '  "expression" : ' + json.dumps(expression) + ',\n'
            '  "tag" : ' + json.dumps(token) + '\n}').encode()


def test_randomized_safe_expressions_and_exact_forwarding():
    token = secrets.token_hex(12)
    ident = 'v_' + secrets.token_hex(8)
    n1 = random.SystemRandom().randint(10000, 999999)
    n2 = random.SystemRandom().randint(10000, 999999)
    expressions = [
        f'({n1} + {n2} * 3) // 2',
        repr(token) + " + '_suffix'",
        ident,
        f'not {ident} or True',
    ]
    for i, expression in enumerate(expressions):
        raw = encode_payload(expression, safe_patch(token + str(i)), token + str(i))
        status, body = send(raw)
        assert status == 200, f'Safe randomized expression was rejected: {expression!r}'
        assert body == expected_backend_body(raw), 'Payload was not forwarded byte-for-byte to the backend'


def test_randomized_forbidden_ast_and_patch_paths_never_reach_backend():
    token = secrets.token_hex(14)
    ident = 'f_' + secrets.token_hex(8)
    patch = safe_patch(token)
    malicious = [
        (f'{ident}({random.randint(10, 9999)})', patch),
        (f'{ident}.attribute_{token}', patch),
        (f'(lambda x: x)({random.randint(10, 9999)})', patch),
        (f'{ident}[{random.randint(0, 9)}]', patch),
        (f'[{ident} for {ident} in ()]', patch),
        ('1 + 2', f'--- /tmp/{token}\t2026-01-01\n+++ b/{token}\n@@ -1 +1 @@\n-x\n+y\n'),
        ('1 + 2', f'--- a/{token}/../../../etc/{token}\n+++ b/{token}\n@@ -1 +1 @@\n-x\n+y\n'),
    ]
    before = capture_count()
    for i, (expression, bad_patch) in enumerate(malicious):
        raw = encode_payload(expression, bad_patch, token + str(i))
        status, _ = send(raw)
        assert status == 403, f'Malicious randomized payload was not blocked: {expression!r}'
    time.sleep(0.2)
    assert capture_count() == before, 'A rejected randomized payload was still sent to the backend'
PY

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
RESULT=$?
if [ "$RESULT" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

python3 /tmp/kill_test_ports.py >/dev/null 2>&1
exit 0
