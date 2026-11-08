#!/bin/bash
set +e
mkdir -p /logs/verifier

# Remove any pre-existing listener on 9090 so verification uses a backend with
# a fresh, unpredictable response that is available only through that port.
python3 <<'PY'
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[3] == '0A':
                    try:
                        port = int(fields[1].rsplit(':', 1)[1], 16)
                    except ValueError:
                        continue
                    if port == 9090:
                        inodes.add(fields[9])
    except OSError:
        pass

pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except OSError:
        pass

for sig in (signal.SIGTERM, signal.SIGKILL):
    for pid in list(pids):
        try:
            os.kill(pid, sig)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.25)
PY

VERIFIER_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
VERIFIER_NONCE="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
export VERIFIER_TOKEN VERIFIER_NONCE

cat > /tmp/verifier_backend.py <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import sys

TOKEN = sys.argv[1]
NONCE = sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split('?', 1)[0]
        if path == '/health':
            body = b'OK'
            status = 200
        elif path == '/__verifier_' + NONCE:
            body = TOKEN.encode()
            status = 200
        else:
            body = b'Not Found'
            status = 404
        self.send_response(status)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

ThreadingHTTPServer(('127.0.0.1', 9090), Handler).serve_forever()
PY

python3 /tmp/verifier_backend.py "$VERIFIER_TOKEN" "$VERIFIER_NONCE" >/tmp/verifier_backend.log 2>&1 &
BACKEND_PID=$!

for _ in $(seq 1 50); do
    if curl -fsS http://127.0.0.1:9090/health >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import urllib.error
import urllib.request
import pytest


def fetch(url):
    response = urllib.request.urlopen(url, timeout=5)
    return response.getcode(), response.read().decode('utf-8').strip()


def test_nginx_fixed():
    """Verify that Nginx proxy is fixed and returns 200 OK with 'OK'."""
    try:
        code, content = fetch('http://127.0.0.1:8080/health')
        assert code == 200, f'Expected HTTP 200, got {code}'
        assert content == 'OK', f"Expected response content 'OK', got '{content}'"
    except urllib.error.HTTPError as e:
        pytest.fail(f'Nginx still returning error: HTTP {e.code}')
    except Exception as e:
        pytest.fail(f'Failed to connect to Nginx: {e}')


def test_nginx_really_proxies_to_9090():
    """Require an unpredictable response served only by the verifier backend on 9090."""
    nonce = os.environ['VERIFIER_NONCE']
    token = os.environ['VERIFIER_TOKEN']
    try:
        code, content = fetch(f'http://127.0.0.1:8080/__verifier_{nonce}')
    except Exception as e:
        pytest.fail(f'Nginx did not proxy the verifier request to port 9090: {e}')
    assert code == 200
    assert content == token, 'Response did not come from the backend listening on port 9090'


def run_waf(waf_path, filepath):
    return subprocess.run(
        [waf_path, filepath], capture_output=True, text=True, timeout=5
    )


def test_waf_script_adversarial_corpus():
    """Retain the original corpus assertions."""
    waf_path = '/home/user/waf.sh'
    assert os.path.isfile(waf_path), f'WAF script {waf_path} does not exist'
    assert os.access(waf_path, os.X_OK), f'WAF script {waf_path} is not executable'

    evil_dir = '/app/corpus/evil/'
    clean_dir = '/app/corpus/clean/'
    assert os.path.isdir(evil_dir), f'Evil corpus directory {evil_dir} missing'
    assert os.path.isdir(clean_dir), f'Clean corpus directory {clean_dir} missing'

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert evil_files, 'No evil files found in corpus'
    assert clean_files, 'No clean files found in corpus'

    evil_bypassed = []
    for name in evil_files:
        result = run_waf(waf_path, os.path.join(evil_dir, name))
        if result.returncode != 1 or result.stdout.strip() != 'REJECT':
            evil_bypassed.append(name)

    clean_modified = []
    for name in clean_files:
        result = run_waf(waf_path, os.path.join(clean_dir, name))
        if result.returncode != 0 or result.stdout.strip() != 'ACCEPT':
            clean_modified.append(name)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(' | '.join(errors))


def test_waf_randomized_hidden_inputs():
    """Use neutral random paths so results must be derived from URI contents."""
    waf_path = '/home/user/waf.sh'
    assert os.path.isfile(waf_path), f'WAF script {waf_path} does not exist'
    assert os.access(waf_path, os.X_OK), f'WAF script {waf_path} is not executable'

    cases = [
        ('../../etc/passwd', 1, 'REJECT'),
        ('/api/v1/../../etc/passwd', 1, 'REJECT'),
        ('%2e%2e%2fshadow', 1, 'REJECT'),
        ('/files/%2E%2E%2Fsecret', 1, 'REJECT'),
        ('/files/%2e%2e/private', 1, 'REJECT'),
        ('/files/..%2fprivate', 1, 'REJECT'),
        ('/files/..%2Fprivate', 1, 'REJECT'),
        ('/api/v1/data', 0, 'ACCEPT'),
        ('/api/v1/users', 0, 'ACCEPT'),
        ('/home/index.html', 0, 'ACCEPT'),
        ('/api/v1/%2e/file', 0, 'ACCEPT'),
        ('/api/v1/..file', 0, 'ACCEPT'),
        ('/search?q=ordinary', 0, 'ACCEPT'),
    ]
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix='waf-inputs-') as directory:
        for uri, expected_code, expected_output in cases:
            filepath = os.path.join(directory, secrets.token_hex(16))
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(uri + '\n')
            result = run_waf(waf_path, filepath)
            if result.returncode != expected_code or result.stdout.strip() != expected_output:
                failures.append(
                    f'{uri!r}: expected ({expected_code}, {expected_output}), '
                    f'got ({result.returncode}, {result.stdout.strip()!r})'
                )
    assert not failures, ' | '.join(failures)
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
STATUS=$?

kill "$BACKEND_PID" >/dev/null 2>&1 || true
wait "$BACKEND_PID" >/dev/null 2>&1 || true

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
