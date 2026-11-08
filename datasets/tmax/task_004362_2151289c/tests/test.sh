#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

# Remove anything the agent may have started before verification. The required
# startup script must recreate all three services itself.
python3 - <<'PY'
import os
import signal
import time

ports = {3000, 6379, 8080}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if len(fields) < 10 or fields[3] != "0A":
                    continue
                port = int(fields[1].split(":")[1], 16)
                if port in ports:
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

pids = set()
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    try:
        for fd in os.listdir(f"/proc/{name}/fd"):
            target = os.readlink(f"/proc/{name}/fd/{fd}")
            if target.startswith("socket:[") and target[8:-1] in inodes:
                pids.add(int(name))
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass

for sig in (signal.SIGTERM, signal.SIGKILL):
    for pid in list(pids):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass
    time.sleep(1)
PY

# Ensure the startup script cannot rely on an already-built or already-running
# submission artifact.
cd /app/rust_api
cargo clean

test -f /home/user/start_services.sh
test -x /home/user/start_services.sh

timeout 240 /home/user/start_services.sh > /tmp/start_services.log 2>&1

# Wait for both the backend and proxy to become healthy.
python3 - <<'PY'
import re
import time
import requests

with open('/app/diagnostics/worker_memory.dump', 'r', errors='ignore') as f:
    match = re.search(r'DIAG_PAYLOAD=([A-Za-z0-9]{32})(?![A-Za-z0-9])', f.read())
assert match, 'Could not derive the diagnostic payload from the memory dump'
payload = match.group(1)

last = None
for _ in range(60):
    try:
        backend = requests.post('http://127.0.0.1:3000/process', json={'payload': payload}, timeout=1)
        proxy = requests.post('http://127.0.0.1:8080/process', json={'payload': payload}, timeout=1)
        if backend.status_code == 200 and proxy.status_code == 200:
            break
    except Exception as exc:
        last = exc
    time.sleep(0.5)
else:
    raise AssertionError(f'Services did not become healthy; last error: {last}')
PY

# Compile and execute the integration regression test requested by the task.
timeout 240 cargo test --manifest-path /app/rust_api/Cargo.toml --test regression_test -- --nocapture

# Validate Redis itself and the exact Nginx configuration used by the process.
redis-cli -h 127.0.0.1 -p 6379 ping | grep -qx PONG
nginx -t -c /app/nginx/nginx.conf

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import re
import secrets
import time

import pytest
import requests


def diagnostic_payload():
    with open('/app/diagnostics/worker_memory.dump', 'r', errors='ignore') as f:
        matches = re.findall(r'DIAG_PAYLOAD=([A-Za-z0-9]{32})(?![A-Za-z0-9])', f.read())
    assert len(matches) == 1, 'Expected exactly one 32-character diagnostic payload in the dump'
    return matches[0]


def listening_socket_pids(port, expected_ipv4=None):
    inodes = set()
    with open('/proc/net/tcp') as f:
        next(f)
        for line in f:
            fields = line.split()
            if len(fields) < 10 or fields[3] != '0A':
                continue
            host_hex, port_hex = fields[1].split(':')
            if int(port_hex, 16) != port:
                continue
            if expected_ipv4 is not None and host_hex != expected_ipv4:
                continue
            inodes.add(fields[9])

    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            for fd in os.listdir(f'/proc/{name}/fd'):
                target = os.readlink(f'/proc/{name}/fd/{fd}')
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return f.read().replace(b'\0', b' ').decode(errors='replace')
    except FileNotFoundError:
        return ''


def executable(pid):
    try:
        return os.path.realpath(f'/proc/{pid}/exe')
    except OSError:
        return ''


def test_start_script_exists():
    script_path = '/home/user/start_services.sh'
    assert os.path.isfile(script_path), f'Startup script missing at {script_path}'
    assert os.access(script_path, os.X_OK), f'Startup script at {script_path} is not executable'


def test_nginx_config_fixed():
    conf_path = '/app/nginx/nginx.conf'
    assert os.path.isfile(conf_path), f'Nginx config missing at {conf_path}'
    with open(conf_path, 'r') as f:
        content = f.read()
    assert '127.0.0.1:3000' in content, 'Nginx config was not updated to proxy to the Rust API on port 3000'
    assert '127.0.0.1:9999' not in content, 'Nginx config still contains the broken port 9999'
    assert re.search(r'proxy_pass\s+http://127\.0\.0\.1:3000\s*;', content), 'Nginx does not contain the required proxy_pass directive'


def test_mre_exists():
    mre_path = '/app/rust_api/tests/regression_test.rs'
    assert os.path.isfile(mre_path), f'MRE test file missing at {mre_path}'
    with open(mre_path, 'r') as f:
        content = f.read()
    assert 'A7x9F22PqL4mN8vC1bY5zR3wK0jH6tDq' in content, 'MRE does not contain the extracted diagnostic payload'
    assert diagnostic_payload() in content, 'MRE does not contain the payload derived from the dump'
    assert re.search(r'#\s*\[\s*(?:tokio::)?test', content), 'MRE is not a Rust integration test'


def test_required_processes_own_listening_sockets():
    # /proc/net/tcp stores 127.0.0.1 as 0100007F.
    nginx_pids = listening_socket_pids(8080, '0100007F')
    assert nginx_pids, 'Nginx is not listening specifically on 127.0.0.1:8080'
    assert any('nginx' in cmdline(pid).lower() for pid in nginx_pids), 'Port 8080 is not owned by Nginx'
    assert any('/app/nginx/nginx.conf' in cmdline(pid) for pid in nginx_pids), 'Running Nginx is not using /app/nginx/nginx.conf'

    rust_pids = listening_socket_pids(3000, '0100007F')
    assert rust_pids, 'Rust API is not listening on 127.0.0.1:3000'
    assert any(executable(pid).startswith('/app/rust_api/target/') and os.path.basename(executable(pid)) == 'rust_api' for pid in rust_pids), 'Port 3000 is not owned by the compiled rust_api project binary'

    redis_pids = listening_socket_pids(6379, '0100007F')
    assert redis_pids, 'Redis is not listening on 127.0.0.1:6379'
    assert any('redis-server' in (cmdline(pid) + ' ' + executable(pid)).lower() for pid in redis_pids), 'Port 6379 is not owned by redis-server'


def test_proxy_and_backend_are_integrated():
    payload = diagnostic_payload()
    direct = requests.post('http://127.0.0.1:3000/process', json={'payload': payload}, timeout=3)
    proxied = requests.post('http://127.0.0.1:8080/process', json={'payload': payload}, timeout=3)
    assert direct.status_code == 200
    assert proxied.status_code == 200
    assert direct.json().get('status') == 'processed'
    assert proxied.json().get('status') == 'processed'

    # An unknown path must be forwarded to Axum as well, rather than answered by
    # a fixed HTTP server installed directly on the proxy port.
    marker = secrets.token_hex(12)
    direct_missing = requests.get(f'http://127.0.0.1:3000/{marker}', timeout=3)
    proxy_missing = requests.get(f'http://127.0.0.1:8080/{marker}', timeout=3)
    assert direct_missing.status_code == 404
    assert proxy_missing.status_code == direct_missing.status_code
    assert proxy_missing.content == direct_missing.content


def test_api_processes_payload_concurrently():
    url = 'http://127.0.0.1:8080/process'
    bad_payload = {'payload': 'A7x9F22PqL4mN8vC1bY5zR3wK0jH6tDq'}
    good_payload = {'payload': 'NormalPayload123'}
    assert bad_payload['payload'] == diagnostic_payload()

    # Include verifier-generated values so a server hard-coded for the original
    # four requests cannot pass. Repeated mixed bursts exercise both former lock
    # orders at the same time.
    generated = [{'payload': secrets.token_urlsafe(24)[:32]} for _ in range(12)]
    payloads = [bad_payload, good_payload] * 6 + generated

    def send_request(payload):
        try:
            response = requests.post(url, json=payload, timeout=5)
            return response
        except requests.exceptions.RequestException as e:
            return e

    for _ in range(3):
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(payloads)) as executor:
            futures = [executor.submit(send_request, p) for p in payloads]
            results = [f.result(timeout=7) for f in concurrent.futures.as_completed(futures)]

        for res in results:
            if isinstance(res, Exception):
                pytest.fail(f'Request failed, possibly due to deadlock or service not running: {res}')
            assert res.status_code == 200, f'Expected status code 200, got {res.status_code}. Response: {res.text}'
            try:
                data = res.json()
            except json.JSONDecodeError:
                pytest.fail(f'Failed to parse JSON response: {res.text}')
            assert data.get('status') == 'processed', f"Expected status 'processed', got {data.get('status')}"
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short
reward=1
