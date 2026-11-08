#!/bin/bash
mkdir -p /logs/verifier

BACKEND_PID=""
PROXY_PID=""
SENTINEL_PID=""

cleanup() {
    [ -n "$SENTINEL_PID" ] && kill "$SENTINEL_PID" 2>/dev/null || true
    [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null || true
    [ -n "$BACKEND_PID" ] && kill "$BACKEND_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Remove any processes already occupying the service ports so the verifier
# exercises the submitted binary and proxy rather than pre-existing servers.
python3 - <<'PY'
import os
import signal

ports = {8000, 8080}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if len(fields) >= 10:
                    port = int(fields[1].rsplit(':', 1)[1], 16)
                    state = fields[3]
                    if port in ports and state == "0A":
                        inodes.add(fields[9])
    except OSError:
        pass

for pid in os.listdir('/proc'):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    fd_dir = f'/proc/{pid}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
PY
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import urllib.request


def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


def fetch(url):
    with urllib.request.urlopen(url, timeout=3) as response:
        assert response.status == 200
        return response.read().decode('utf-8').strip()


def test_test_results_exists_and_correct():
    path = "/home/user/test_results.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the integration test?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "55", f"Expected test_results.txt to contain '55', but got '{content}'. The math logic or proxy might not be working correctly."


def test_rust_backend_built():
    path = "/home/user/rust_backend/target/release/rust_backend"
    assert os.path.isfile(path), f"Compiled Rust binary {path} is missing. Did you run 'cargo build --release'?"
    assert os.access(path, os.X_OK), f"Compiled Rust binary {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary."
    assert os.path.getmtime(path) >= os.path.getmtime('/home/user/rust_backend/src/main.rs'), "The release binary is older than src/main.rs; rebuild after applying the patch."


def test_patch_applied():
    path = "/home/user/rust_backend/src/main.rs"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert "if n <= 1" in content, "The patch does not seem to be applied to src/main.rs."


def test_proxy_python3_syntax():
    path = "/home/user/proxy.py"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read()

    assert not re.search(r"except Exception,\s*e:", content), "Found Python 2 exception syntax in proxy.py."
    assert not re.search(r"print\s+[\"']", content), "Found Python 2 print statement in proxy.py."
    assert "http.server" in content or "urllib.request" in content, "proxy.py does not seem to use Python 3 modules (e.g., http.server, urllib.request)."


def test_launched_services_are_alive():
    for name in ('BACKEND_PID', 'PROXY_PID'):
        pid = int(os.environ[name])
        os.kill(pid, 0)


def test_backend_and_proxy_on_derived_inputs():
    rng = secrets.SystemRandom()
    values = [0, 1] + rng.sample(range(2, 21), 7)
    for n in values:
        expected = str(fib(n))
        assert fetch(f"http://127.0.0.1:8080/fib/{n}") == expected
        assert fetch(f"http://127.0.0.1:8000/fib/{n}") == expected
TEST_EOF

run_services_and_integration() {
    python3 -m py_compile /home/user/proxy.py || return 1
    [ -x /home/user/rust_backend/target/release/rust_backend ] || return 1

    # First put an unpredictable verifier-controlled response behind the proxy.
    # This establishes that proxy.py really forwards requests to port 8080.
    PROXY_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(24))')" || return 1
    PROXY_PATH="/probe-$(python3 -c 'import secrets; print(secrets.token_hex(12))')" || return 1
    export PROXY_TOKEN PROXY_PATH
    cat <<'PY' > /tmp/sentinel_backend.py
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != os.environ['PROXY_PATH']:
            self.send_response(404)
            self.end_headers()
            return
        body = os.environ['PROXY_TOKEN'].encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

HTTPServer(('127.0.0.1', 8080), Handler).serve_forever()
PY
    python3 /tmp/sentinel_backend.py >/tmp/sentinel.log 2>&1 &
    SENTINEL_PID=$!

    python3 /home/user/proxy.py >/tmp/proxy.log 2>&1 &
    PROXY_PID=$!

    python3 - <<'PY' || return 1
import os, time, urllib.request
url = 'http://127.0.0.1:8000' + os.environ['PROXY_PATH']
last = None
for _ in range(50):
    try:
        with urllib.request.urlopen(url, timeout=1) as r:
            value = r.read().decode()
        if value == os.environ['PROXY_TOKEN']:
            raise SystemExit(0)
        last = RuntimeError('proxy returned the wrong sentinel body')
    except Exception as e:
        last = e
        time.sleep(0.1)
raise SystemExit(str(last))
PY

    kill "$SENTINEL_PID" 2>/dev/null || return 1
    wait "$SENTINEL_PID" 2>/dev/null || true
    SENTINEL_PID=""
    sleep 0.3

    /home/user/rust_backend/target/release/rust_backend >/tmp/rust_backend.log 2>&1 &
    BACKEND_PID=$!

    python3 - <<'PY' || return 1
import time, urllib.request
last = None
for _ in range(50):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8080/fib/1', timeout=1) as r:
            if r.read().decode().strip() == '1':
                raise SystemExit(0)
        last = RuntimeError('backend returned an incorrect startup response')
    except Exception as e:
        last = e
        time.sleep(0.1)
raise SystemExit(str(last))
PY

    rm -f /home/user/test_results.txt
    timeout 10s python3 /home/user/test_integration.py || return 1
    [ -f /home/user/test_results.txt ] || return 1
    return 0
}

if run_services_and_integration; then
    export BACKEND_PID PROXY_PID
    if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        echo "1" > /logs/verifier/reward.txt
    else
        echo "0" > /logs/verifier/reward.txt
    fi
else
    echo "0" > /logs/verifier/reward.txt
fi
