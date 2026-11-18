#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'VERIFY_EOF' > /tmp/run_verifier.sh
#!/bin/bash
set -euo pipefail

API_PID=""
PROXY_PID=""
STUB_PID=""
cleanup() {
    [ -z "$API_PID" ] || kill "$API_PID" 2>/dev/null || true
    [ -z "$PROXY_PID" ] || kill "$PROXY_PID" 2>/dev/null || true
    [ -z "$STUB_PID" ] || kill "$STUB_PID" 2>/dev/null || true
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import urllib.request
import pytest

def test_libsecret_so_exists():
    path = "/home/user/legacy/libsecret.so"
    assert os.path.isfile(path), f"Shared library {path} was not created"

def test_final_output_json():
    path = "/home/user/final_output.json"
    assert os.path.isfile(path), f"Output file {path} does not exist"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON")

    assert data.get("status") == "success", f"Expected 'status' to be 'success' in {path}"
    assert data.get("data") == "API_KEY_998877", f"Expected 'data' to be 'API_KEY_998877' in {path}"

def test_api_service_running():
    url = "http://127.0.0.1:8080/secret"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"API service at {url} did not return 200 OK"
            content_type = response.headers.get("Content-Type", "")
            assert "application/json" in content_type, f"API service did not set Content-Type: application/json (got {content_type})"

            data = json.loads(response.read().decode("utf-8"))
            assert data.get("status") == "success", "API service JSON response status mismatch"
            assert data.get("data") == "API_KEY_998877", "API service JSON response data mismatch"
    except Exception as e:
        pytest.fail(f"Failed to connect to API service on 8080 or invalid response: {e}")

def test_proxy_service_running():
    url = "http://127.0.0.1:9090/secret"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Proxy service at {url} did not return 200 OK"

            headers = {k.lower(): v for k, v in response.getheaders()}
            assert headers.get("x-proxy-routed", "").lower() == "true", "Proxy did not inject 'X-Proxy-Routed: true' header"

            data = json.loads(response.read().decode("utf-8"))
            assert data.get("status") == "success", "Proxy service JSON response status mismatch"
            assert data.get("data") == "API_KEY_998877", "Proxy service JSON response data mismatch"
    except Exception as e:
        pytest.fail(f"Failed to connect to Proxy service on 9090 or invalid response: {e}")
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short

# The submitted library must really be a shared object exporting the required API.
readelf -h /home/user/legacy/libsecret.so >/dev/null
nm -D --defined-only /home/user/legacy/libsecret.so | grep -Eq '[[:space:]]get_encoded_secret$'
[ -f /home/user/api/main.go ]
[ -f /home/user/proxy/main.go ]

cat << 'KILL_EOF' > /tmp/kill_listeners.py
import glob
import os
import signal
import sys
import time

ports = {int(x) for x in sys.argv[1:]}
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if len(fields) > 9 and fields[3] == "0A":
            port = int(fields[1].rsplit(":", 1)[1], 16)
            if port in ports:
                inodes.add(fields[9])
for proc in glob.glob("/proc/[0-9]*"):
    try:
        pid = int(proc.rsplit("/", 1)[1])
        if pid == os.getpid():
            continue
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                os.kill(pid, signal.SIGKILL)
                break
    except (OSError, ValueError):
        pass
time.sleep(0.3)
KILL_EOF

python3 /tmp/kill_listeners.py 8080 9090

# Install an unpredictable instrumented implementation. Its marker proves that
# the submitted API actually invokes get_encoded_secret rather than merely
# reproducing a known response.
make_challenge_lib() {
    local marker="$1"
    local metadata="$2"
    MARKER="$marker" METADATA="$metadata" python3 - <<'PY'
import json, os, secrets
secret = "DYN_" + secrets.token_hex(16)
encoded = bytes((b ^ 0x55) for b in secret.encode()).hex()
marker = os.environ["MARKER"]
source = r'''#include "secret.h"
#include <fcntl.h>
#include <unistd.h>
const char* get_encoded_secret(void) {
    int fd = open("%s", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) { write(fd, "1", 1); close(fd); }
    return "%s";
}
''' % (marker, encoded)
open("/tmp/challenge_secret.c", "w").write(source)
json.dump({"secret": secret, "marker": marker}, open(os.environ["METADATA"], "w"))
PY
    rm -f "$marker"
    gcc -shared -fPIC -Wl,-soname,libsecret.so \
        -I/home/user/legacy -o /home/user/legacy/libsecret.so /tmp/challenge_secret.c
}

make_challenge_lib /tmp/libsecret_called_1 /tmp/challenge_1.json
(
    cd /home/user/api
    CGO_ENABLED=1 go build -o /tmp/submitted_api main.go
)

# Require a dynamic dependency on libsecret and a call-site relocation for the
# legacy function; the behavioral checks below verify decoding of its result.
readelf -d /tmp/submitted_api | grep -Eq 'NEEDED.*libsecret\.so'
nm -D /tmp/submitted_api | grep -Eq '[[:space:]]U[[:space:]]+get_encoded_secret$'

run_api_check() {
    local metadata="$1"
    LD_LIBRARY_PATH=/home/user/legacy /tmp/submitted_api >/tmp/api.log 2>&1 &
    API_PID=$!
    METADATA="$metadata" python3 - <<'PY'
import json, os, time, urllib.request
meta = json.load(open(os.environ["METADATA"]))
last = None
for _ in range(50):
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080/secret", timeout=1) as r:
            assert r.status == 200
            assert "application/json" in r.headers.get("Content-Type", "")
            data = json.loads(r.read().decode("utf-8"))
            assert data.get("status") == "success"
            assert data.get("data") == meta["secret"], (data, meta["secret"])
            break
    except Exception as exc:
        last = exc
        time.sleep(0.1)
else:
    raise AssertionError(f"challenge API did not produce the library-derived secret: {last}")
assert os.path.isfile(meta["marker"]), "get_encoded_secret was not invoked"
assert os.path.getsize(meta["marker"]) > 0, "get_encoded_secret marker is empty"
PY
    kill "$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
    API_PID=""
    python3 /tmp/kill_listeners.py 8080
}

run_api_check /tmp/challenge_1.json

# Change only the shared library and rerun the same compiled API. This checks
# both dynamic linking and general hex/XOR decoding rather than one fixed token.
make_challenge_lib /tmp/libsecret_called_2 /tmp/challenge_2.json
run_api_check /tmp/challenge_2.json

(
    cd /home/user/proxy
    go build -o /tmp/submitted_proxy main.go
)

# Use a derived upstream response on 8080 and ensure requests and responses are
# genuinely relayed by the submitted proxy, including non-GET requests.
NONCE="$(python3 -c 'import secrets; print(secrets.token_hex(20))')"
export NONCE
cat << 'STUB_EOF' > /tmp/upstream_stub.py
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

nonce = os.environ["NONCE"]
class Handler(BaseHTTPRequestHandler):
    def handle_request(self):
        length = int(self.headers.get("Content-Length", "0"))
        incoming = self.rfile.read(length).decode("utf-8")
        body = json.dumps({
            "nonce": nonce,
            "method": self.command,
            "target": self.path,
            "body": incoming,
        }, separators=(",", ":")).encode()
        self.send_response(201)
        self.send_header("Content-Type", "application/x-verifier-upstream")
        self.send_header("X-Upstream-Nonce", nonce)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    do_GET = handle_request
    do_POST = handle_request
    def log_message(self, *args):
        pass
ThreadingHTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
STUB_EOF
python3 /tmp/upstream_stub.py >/tmp/upstream.log 2>&1 &
STUB_PID=$!

python3 - <<'PY'
import socket, time
for _ in range(50):
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=.2):
            break
    except OSError:
        time.sleep(.1)
else:
    raise AssertionError("upstream stub failed to start")
PY

/tmp/submitted_proxy >/tmp/proxy.log 2>&1 &
PROXY_PID=$!
python3 - <<'PY'
import json, os, time, urllib.request
nonce = os.environ["NONCE"]
cases = [
    ("GET", "/secret?probe=" + nonce[:8], b""),
    ("POST", "/forward/arbitrary?mode=test", ("payload-" + nonce).encode()),
]
for method, target, payload in cases:
    last = None
    for _ in range(50):
        try:
            req = urllib.request.Request(
                "http://127.0.0.1:9090" + target,
                data=(payload if method == "POST" else None),
                method=method,
            )
            with urllib.request.urlopen(req, timeout=1) as response:
                assert response.status == 201
                assert response.headers.get("X-Proxy-Routed", "").lower() == "true"
                assert response.headers.get("X-Upstream-Nonce") == nonce
                assert response.headers.get("Content-Type") == "application/x-verifier-upstream"
                data = json.loads(response.read().decode())
                assert data == {
                    "nonce": nonce,
                    "method": method,
                    "target": target,
                    "body": payload.decode(),
                }
                break
        except Exception as exc:
            last = exc
            time.sleep(.1)
    else:
        raise AssertionError(f"proxy did not forward {method} {target}: {last}")
PY
VERIFY_EOF

if bash /tmp/run_verifier.sh 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
