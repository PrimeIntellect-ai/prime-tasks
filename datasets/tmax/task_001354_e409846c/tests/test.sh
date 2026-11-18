#!/bin/bash
mkdir -p /logs/verifier

if (
set -e

# Ensure pre-existing or fake listeners cannot mask a broken build/startup.
python3 - <<'PY'
import os
import signal
import time

ports = {8080, 8081}
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                local = fields[1]
                state = fields[3]
                inode = fields[9]
                port = int(local.rsplit(':', 1)[1], 16)
                if port in ports and state == '0A':
                    inodes.add(inode)
    except FileNotFoundError:
        pass

victims = set()
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
                victims.add(int(name))
                break
    except (FileNotFoundError, PermissionError):
        pass

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
PY

# Force start.sh to perform both builds rather than relying on stale artifacts.
rm -rf /home/user/app/backend/ctrie/build
rm -f /home/user/app/backend/ctrie.so /home/user/app/proxy/proxy
cd /home/user/app
setsid bash /home/user/app/start.sh >/tmp/verifier-app-start.log 2>&1 &
START_PID=$!

# Both independently-addressable services must come up, and start.sh must remain alive.
python3 - "$START_PID" <<'PY'
import socket
import sys
import time

pid = int(sys.argv[1])
deadline = time.time() + 45
while time.time() < deadline:
    try:
        import os
        os.kill(pid, 0)
        ready = True
        for port in (8080, 8081):
            s = socket.create_connection(('127.0.0.1', port), timeout=0.5)
            s.close()
        if ready:
            sys.exit(0)
    except (OSError, ProcessLookupError):
        pass
    time.sleep(0.25)
print(open('/tmp/verifier-app-start.log', errors='replace').read(), file=sys.stderr)
sys.exit(1)
PY

cat <<'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import importlib.util
import json
import os
import random
import signal
import string
import subprocess
import sys
import time
import urllib.error
import urllib.request

import pytest

APP_DIR = "/home/user/app"
CLEAN_DIR = os.path.join(APP_DIR, "corpora", "clean")
EVIL_DIR = os.path.join(APP_DIR, "corpora", "evil")
PROXY_URL = "http://127.0.0.1:8080/"
BACKEND_URL = "http://127.0.0.1:8081/"


def request_bytes(url, data, timeout=5):
    req = urllib.request.Request(
        url, data=data, headers={'Content-Type': 'application/json'}, method='POST'
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception:
        return 0, b''


def send_request(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    return request_bytes(PROXY_URL, data)[0]


def random_token():
    return ''.join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(28))


def listening_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].rsplit(':', 1)[1], 16) == port and fields[3] == '0A':
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    result = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            for fd in os.listdir('/proc/%s/fd' % name):
                try:
                    target = os.readlink('/proc/%s/fd/%s' % (name, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return result


def test_extension_was_built_and_imports_under_python3():
    so_path = os.path.join(APP_DIR, 'backend', 'ctrie.so')
    proxy_binary = os.path.join(APP_DIR, 'proxy', 'proxy')
    assert os.path.isfile(so_path), 'start.sh did not build backend/ctrie.so'
    assert os.path.isfile(proxy_binary), 'start.sh did not build the Go proxy binary'
    with open(so_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'ctrie.so is not an ELF shared object'
    with open(proxy_binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'proxy output is not an ELF executable'

    code = (
        "import ctrie; "
        "assert ctrie.__file__.endswith('.so'); "
        "assert ctrie.init() is None"
    )
    subprocess.run(
        [sys.executable, '-c', code],
        cwd=os.path.join(APP_DIR, 'backend'),
        check=True,
        timeout=10,
    )


def test_python3_backend_and_proxy_handle_derived_request():
    payload = json.dumps({'query': 'derived-' + random_token(), 'is_admin': False}).encode()
    direct_status, direct_body = request_bytes(BACKEND_URL, payload)
    proxy_status, proxy_body = request_bytes(PROXY_URL, payload)
    assert direct_status == 200, f'Python backend on 8081 returned {direct_status}'
    assert proxy_status == 200, f'Proxy returned {proxy_status} for a derived clean request'
    assert json.loads(direct_body.decode()) == {'status': 'ok'}
    assert proxy_body == direct_body
    time.sleep(1.25)


def test_derived_validation_cases():
    cases = [
        ({'query': random_token() + 'OR 1=1' + random_token(), 'is_admin': False}, 403),
        ({'query': random_token(), 'is_admin': True}, 403),
        ({'query': random_token() + 'or 1=1', 'is_admin': False}, 200),
        ({'query': random_token() + 'OR 1 =1', 'is_admin': False}, 200),
    ]
    for obj, expected in cases:
        status, _ = request_bytes(PROXY_URL, json.dumps(obj).encode())
        assert status == expected, f'derived payload {obj!r} returned {status}, expected {expected}'
        time.sleep(0.3)


def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.json')]
    bypassed = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        status = send_request(filepath)
        if status != 403:
            bypassed.append((filename, status))
        time.sleep(0.25)

    if bypassed:
        offending = ", ".join([f"{f} (status {s})" for f, s in bypassed])
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {offending}")


def test_clean_corpus_accepted():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.json')]
    modified = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        status = send_request(filepath)
        if status != 200:
            modified.append((filename, status))
        time.sleep(0.25)

    if modified:
        offending = ", ".join([f"{f} (status {s})" for f, s in modified])
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified (failed to return 200): {offending}")


def test_rate_limiting():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.json')]
    if not clean_files:
        pytest.skip("No clean files available for rate limit test")

    filepath = os.path.join(CLEAN_DIR, clean_files[0])
    time.sleep(1.25)

    def worker(_):
        return send_request(filepath)

    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        results = list(executor.map(worker, range(20)))

    count_429 = results.count(429)
    count_200 = results.count(200)
    assert count_429 == 15, f"Expected 15 requests to return 429, but got {count_429}. Results: {results}"
    assert count_200 == 5, f"Expected 5 requests to succeed, but got {count_200}. Results: {results}"


def test_proxy_really_depends_on_backend_and_restore_service():
    time.sleep(1.25)
    pids = listening_pids(8081)
    assert pids, 'No backend process is listening on port 8081'
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline and listening_pids(8081):
        time.sleep(0.1)
    for pid in listening_pids(8081):
        os.kill(pid, signal.SIGKILL)
    assert not listening_pids(8081), 'Could not stop backend for forwarding check'

    payload = json.dumps({'query': 'routing-probe-' + random_token(), 'is_admin': False}).encode()
    status, _ = request_bytes(PROXY_URL, payload, timeout=3)
    assert status != 200, 'Proxy returned a successful canned response while backend was unavailable'

    backend_dir = os.path.join(APP_DIR, 'backend')
    subprocess.Popen(
        [sys.executable, 'server.py'],
        cwd=backend_dir,
        stdout=open('/tmp/verifier-backend-restart.log', 'ab'),
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    deadline = time.time() + 10
    while time.time() < deadline:
        status, _ = request_bytes(BACKEND_URL, payload, timeout=1)
        if status == 200:
            break
        time.sleep(0.2)
    else:
        pytest.fail('Python backend did not recover after the routing check')

    time.sleep(1.25)
    status, _ = request_bytes(PROXY_URL, payload)
    assert status == 200, f'Proxy did not resume forwarding after backend restart: {status}'
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
