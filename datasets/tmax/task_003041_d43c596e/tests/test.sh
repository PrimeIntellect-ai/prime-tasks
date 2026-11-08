#!/bin/bash
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

SERVER=/home/user/pr/server.sh
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill -TERM -- "-$SERVER_PID" 2>/dev/null || true
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        sleep 0.2
        kill -KILL -- "-$SERVER_PID" 2>/dev/null || true
        kill -KILL "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# The submitted artifact must be a real executable Bash script with valid syntax.
if [ ! -f "$SERVER" ] || [ -L "$SERVER" ] || [ ! -x "$SERVER" ]; then
    exit 0
fi
if ! bash -n "$SERVER"; then
    exit 0
fi

# Stop anything the agent left on port 8080, then execute the submitted artifact
# ourselves so the behavior under test must come from server.sh.
python3 - <<'PY'
import os
import signal
import time

PORT_HEX = "1F90"

def listener_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    cols = line.split()
                    if len(cols) >= 10 and cols[1].upper().endswith(":" + PORT_HEX) and cols[3] == "0A":
                        found.add(cols[9])
        except OSError:
            pass
    return found

def holders(inodes):
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids

for sig in (signal.SIGTERM, signal.SIGKILL):
    for _ in range(10):
        pids = holders(listener_inodes())
        if not pids:
            break
        for pid in pids:
            if pid not in (1, os.getpid(), os.getppid()):
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        time.sleep(0.1)
PY

(cd /home/user/pr && exec setsid ./server.sh) >/tmp/submitted-server.log 2>&1 &
SERVER_PID=$!

# Wait for the freshly launched server to accept TCP connections.
if ! python3 - <<'PY'
import socket
import time
for _ in range(60):
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit(1)
PY
then
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import secrets
import string
import threading
import time
import urllib.error
import urllib.request

import pytest

TOKEN = "blue flamingo dances brightly"
PORT = 8080
URL = f"http://127.0.0.1:{PORT}/webhook"


def request(method="POST", url=URL, token=TOKEN, payload=None, raw=None):
    req = urllib.request.Request(url, method=method)
    if token is not None:
        req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    if raw is None and payload is not None:
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    try:
        with urllib.request.urlopen(req, data=raw, timeout=3) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", errors="replace")


def expected_body(repo, branch):
    return f"Build triggered for repo: {repo} on branch: {branch}"


def test_webhook_server_unauthorized():
    """Check that the server returns 401 for missing or incorrect auth token."""
    req = urllib.request.Request(URL, method="POST")
    req.add_header("Authorization", "Bearer wrong token")
    req.add_header("Content-Type", "application/json")
    data = json.dumps({"repo": "test", "branch": "main"}).encode("utf-8")

    try:
        urllib.request.urlopen(req, data=data, timeout=2)
        pytest.fail("Server should have rejected the request with 401 Unauthorized")
    except urllib.error.HTTPError as e:
        assert e.code == 401, f"Expected 401 Unauthorized, got {e.code}"
    except Exception as e:
        pytest.fail(f"Unexpected error when testing unauthorized access: {e}")


def test_authentication_is_general_not_one_fixed_token():
    payload = {"repo": "auth-check", "branch": "main"}
    status, _ = request(token=None, payload=payload)
    assert status == 401

    wrong_tokens = [
        "",
        TOKEN + "x",
        "x" + TOKEN,
        TOKEN.upper(),
        TOKEN[:-1],
    ]
    wrong_tokens.extend(secrets.token_urlsafe(18) for _ in range(7))
    for wrong in wrong_tokens:
        assert wrong != TOKEN
        status, _ = request(token=wrong, payload=payload)
        assert status == 401, f"Incorrect token {wrong!r} was not rejected with 401"


def test_route_and_method_are_restricted():
    payload = {"repo": "route-check", "branch": "main"}
    suffix = secrets.token_hex(8)
    for bad_url in (
        f"http://127.0.0.1:{PORT}/",
        f"http://127.0.0.1:{PORT}/webhook/{suffix}",
        f"http://127.0.0.1:{PORT}/{suffix}",
    ):
        status, _ = request(url=bad_url, payload=payload)
        assert not 200 <= status < 300, f"Unexpected success for route {bad_url}"

    for method in ("GET", "PUT", "DELETE", "PATCH"):
        status, _ = request(method=method, payload=payload)
        assert not 200 <= status < 300, f"Unexpected success for method {method}"


def test_json_is_parsed_and_dynamic_values_are_returned_safely():
    alphabet = string.ascii_letters + string.digits + " _-./"
    cases = []
    for _ in range(18):
        repo = "repo-" + "".join(secrets.choice(alphabet) for _ in range(20))
        branch = "branch-" + "".join(secrets.choice(alphabet) for _ in range(24))
        cases.append((repo, branch))

    # These require correct JSON unescaping rather than matching one fixed body.
    cases.extend([
        ('quoted "repo" and \\ slash', "feature/it's-safe"),
        ("spaces and [brackets]", "semi; amp& pipe| dollar$"),
        ("line\\ttext", "$(printf harmless) `printf harmless`"),
    ])

    for repo, branch in cases:
        # Alternate key order and formatting to ensure an actual JSON object is read.
        if secrets.randbits(1):
            raw = json.dumps({"branch": branch, "repo": repo}, indent=2).encode("utf-8")
            status, body = request(raw=raw)
        else:
            status, body = request(payload={"repo": repo, "branch": branch})
        assert status == 200
        assert body.rstrip("\r\n") == expected_body(repo, branch)


def test_command_payload_is_literal_and_has_no_side_effect():
    marker = f"/tmp/webhook-injection-{secrets.token_hex(12)}"
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass
    repo = f"repo; touch {marker}"
    branch = f"$(touch {marker}); `touch {marker}`; main"
    status, body = request(payload={"branch": branch, "repo": repo})
    assert status == 200
    assert body.rstrip("\r\n") == expected_body(repo, branch)
    time.sleep(0.1)
    assert not os.path.exists(marker), "Payload caused command execution"


def test_malformed_or_incomplete_json_is_not_accepted():
    invalid_bodies = [
        b"not json",
        b'{"repo":"x","branch":}',
        b'[]',
        b'{"repo":"only-repo"}',
        b'{"branch":"only-branch"}',
        b'{"repo":12,"branch":"main"}',
    ]
    for raw in invalid_bodies:
        status, _ = request(raw=raw)
        assert not 200 <= status < 300, f"Malformed payload was accepted: {raw!r}"


def test_concurrent_distinct_requests():
    cases = [(f"repo-{secrets.token_hex(5)}", f"branch-{secrets.token_hex(6)}") for _ in range(40)]

    def one(case):
        repo, branch = case
        status, body = request(payload={"repo": repo, "branch": branch})
        return status, body.rstrip("\r\n"), expected_body(repo, branch)

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        results = list(pool.map(one, cases))
    for status, body, expected in results:
        assert status == 200
        assert body == expected


def test_webhook_server_performance_and_correctness():
    """Check that the server processes requests correctly and meets the RPS threshold."""
    success_count = 0
    total_count = 200
    errors = 0

    lock = threading.Lock()

    def worker():
        nonlocal success_count, errors
        for _ in range(20):
            req = urllib.request.Request(URL, method="POST")
            req.add_header("Authorization", f"Bearer {TOKEN}")
            req.add_header("Content-Type", "application/json")
            data = json.dumps({"repo": "test-repo", "branch": "main; rm -rf /"}).encode("utf-8")
            try:
                resp = urllib.request.urlopen(req, data=data, timeout=2)
                body = resp.read().decode("utf-8")
                if resp.status == 200 and "main; rm -rf /" in body and "test-repo" in body:
                    with lock:
                        success_count += 1
                else:
                    with lock:
                        errors += 1
            except Exception:
                with lock:
                    errors += 1

    start = time.time()
    threads = []
    for _ in range(10):
        t = threading.Thread(target=worker)
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    duration = time.time() - start
    rps = total_count / duration

    assert errors == 0, f"Expected 0 errors, got {errors}. Server might be crashing or returning wrong status/body."
    assert success_count == total_count, f"Expected {total_count} successful requests, got {success_count}."

    threshold = 25.0
    assert rps >= threshold, f"Throughput too low: measured {rps:.2f} RPS, expected >= {threshold} RPS."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
