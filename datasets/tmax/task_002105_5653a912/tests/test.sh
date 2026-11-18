#!/bin/bash
set -e
mkdir -p /logs/verifier

INSTR=""
BIN="/tmp/verifier_service_$$"
SOCK="/tmp/verifier_goroutines_$$.sock"
cleanup() {
    if [ -n "$INSTR" ]; then rm -f "$INSTR"; fi
}
trap cleanup EXIT

run_verification() {
    # Preserve the original requirement that the agent left a service running.
    python3 - <<'PY'
import urllib.request
try:
    with urllib.request.urlopen("http://127.0.0.1:8080/goroutines", timeout=2) as r:
        int(r.read().decode().strip())
except Exception as e:
    raise SystemExit(f"Agent did not leave a working service on port 8080: {e}")
PY

    cd /app/vendored_service
    INSTR="/app/vendored_service/zz_verifier_metrics_$$.go"
    cat > "$INSTR" <<EOF
package main

import (
    "fmt"
    "net"
    "os"
    "runtime"
)

func init() {
    const socketPath = "$SOCK"
    _ = os.Remove(socketPath)
    go func() {
        ln, err := net.Listen("unix", socketPath)
        if err != nil {
            return
        }
        for {
            conn, err := ln.Accept()
            if err != nil {
                return
            }
            _, _ = fmt.Fprintf(conn, "%d", runtime.NumGoroutine())
            _ = conn.Close()
        }
    }()
}
EOF

    # Build the submitted service with a verifier-owned, same-process goroutine
    # counter. The HTTP /goroutines response is therefore not trusted.
    go build -o "$BIN" .
    rm -f "$INSTR"
    INSTR=""

    # Stop whichever process currently owns port 8080, then execute the artifact
    # built from the submitted source.
    python3 - <<'PY'
import glob
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == '1F90' and fields[3] == '0A':
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

pids = set()
for proc in glob.glob('/proc/[0-9]*'):
    try:
        pid = int(proc.rsplit('/', 1)[-1])
        for fd in glob.glob(proc + '/fd/*'):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(pid)
                break
    except (ValueError, PermissionError, FileNotFoundError):
        pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.3)
for pid in pids:
    try:
        os.kill(pid, 0)
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY

    rm -f "$SOCK"
    nohup "$BIN" </dev/null >/tmp/verifier_service.log 2>&1 &
    SERVICE_PID=$!

    export VERIFIER_SOCK="$SOCK"
    python3 - <<'PY'
import json
import os
import random
import socket
import struct
import time
import urllib.error
import urllib.request
import uuid

BASE = "http://127.0.0.1:8080"
SOCK = os.environ["VERIFIER_SOCK"]

# Wait for both the submitted HTTP server and the verifier-owned metric socket.
deadline = time.time() + 8
last_error = None
while time.time() < deadline:
    try:
        with urllib.request.urlopen(BASE + "/goroutines", timeout=0.5) as r:
            int(r.read().decode().strip())
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(SOCK)
        int(s.recv(128).decode().strip())
        s.close()
        break
    except Exception as e:
        last_error = e
        time.sleep(0.1)
else:
    raise AssertionError(f"Built service failed to start: {last_error}")

def trusted_goroutines():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect(SOCK)
    chunks = []
    while True:
        data = s.recv(128)
        if not data:
            break
        chunks.append(data)
    s.close()
    return int(b''.join(chunks).decode().strip())

def public_goroutines():
    with urllib.request.urlopen(BASE + "/goroutines", timeout=2) as r:
        return int(r.read().decode().strip())

def post(raw, timeout=2):
    req = urllib.request.Request(
        BASE + "/process",
        data=raw,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")

# Keep the original public-endpoint assertion, but do not rely on it for leaks.
public_baseline = public_goroutines()
trusted_baseline = trusted_goroutines()

# Exercise unpredictable valid payloads rather than one fixed fixture.
valid_values = [
    "v-" + uuid.uuid4().hex,
    "quotes-\\\"-" + uuid.uuid4().hex,
    "unicode-雪-" + uuid.uuid4().hex,
    "line\\n" + uuid.uuid4().hex,
]
for value in valid_values:
    status, body = post(json.dumps({"data": value}).encode())
    assert status == 200, f"Expected HTTP 200 for valid JSON, got {status}"
    assert body == "processed", f"Expected 'processed', got {body!r}"

# Test several independently generated corruption forms.
token = uuid.uuid4().hex
malformed = [
    ('{"data":' + json.dumps(token)).encode(),
    ('{"data":"' + token[:random.randint(1, len(token)-1)]).encode(),
    ('{"data":' + json.dumps(token) + ',}').encode(),
    ('{"data": tru' + token[:4]).encode(),
    ('{"data":' + json.dumps(token) + '}}').encode(),
    ('{"data":' + json.dumps(token) + '} trailing-' + uuid.uuid4().hex).encode(),
]
for raw in malformed:
    try:
        status, _ = post(raw, timeout=1.5)
    except (TimeoutError, socket.timeout, urllib.error.URLError) as e:
        raise AssertionError(f"Service hung on corrupted JSON input: {e}")
    assert status == 400, f"Expected HTTP 400 for malformed payload {raw!r}, got {status}"

# Send complete requests and immediately reset each connection, ensuring the
# server sees real client cancellation without depending on requests' timeout behavior.
for _ in range(60):
    value = uuid.uuid4().hex
    body = json.dumps({"data": value}).encode()
    request = (
        b"POST /process HTTP/1.1\r\n"
        b"Host: 127.0.0.1:8080\r\n"
        b"Content-Type: application/json\r\n"
        + f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode()
        + body
    )
    s = socket.create_connection(("127.0.0.1", 8080), timeout=1)
    s.sendall(request)
    time.sleep(random.uniform(0.001, 0.005))
    s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
    s.close()

# The original worker delay is 200ms; this permits all non-leaking workers and
# request handlers ample time to terminate.
time.sleep(0.8)
trusted_final = trusted_goroutines()
public_final = public_goroutines()

assert trusted_final <= trusted_baseline + 1, (
    f"Goroutine leak detected by same-process verifier counter: "
    f"baseline={trusted_baseline}, final={trusted_final}"
)
assert public_final <= public_baseline + 1, (
    f"Public goroutine count increased: baseline={public_baseline}, final={public_final}"
)
PY
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
