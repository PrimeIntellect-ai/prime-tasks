#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
finish() {
    echo "$reward" > /logs/verifier/reward.txt
}
trap finish EXIT

DAEMON_DIR=/home/user/auth_daemon
DAEMON="$DAEMON_DIR/daemon"

# Remove any process already listening on port 9000 so the verified build is the
# process that serves the tests.
python3 - <<'PY'
import glob, os, signal, time
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].split(":")[-1].upper() == "2328" and fields[3] == "0A":
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass
pids = set()
for fd in glob.glob("/proc/[0-9]*/fd/*"):
    try:
        target = os.readlink(fd)
        if target.startswith("socket:[") and target[8:-1] in inodes:
            pids.add(int(fd.split("/")[2]))
    except (FileNotFoundError, PermissionError, OSError, ValueError):
        pass
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.3)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY

cd "$DAEMON_DIR"
test -f daemon.c
test -f Makefile
make clean
make
python3 - <<'PY'
import os
p = "/home/user/auth_daemon/daemon"
assert os.path.isfile(p), "Makefile did not produce the daemon executable"
assert os.access(p, os.X_OK), "Built daemon is not executable"
with open(p, "rb") as f:
    assert f.read(4) == b"\x7fELF", "Makefile output is not a compiled ELF executable"
assert os.stat(p).st_mtime_ns >= os.stat("/home/user/auth_daemon/daemon.c").st_mtime_ns
PY

./daemon >/tmp/auth_daemon.verifier.log 2>&1 &
DAEMON_PID=$!
export DAEMON_PID
sleep 0.5
kill -0 "$DAEMON_PID"
python3 - <<'PY'
import os
pid = int(os.environ["DAEMON_PID"])
expected = os.path.realpath("/home/user/auth_daemon/daemon")
actual = os.path.realpath(f"/proc/{pid}/exe")
assert actual == expected, f"Running process is {actual}, not the Makefile-built daemon"
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.server
import os
import re
import secrets
import signal
import socket
import stat
import string
import subprocess
import threading
import time

import pytest

DAEMON_DIR = "/home/user/auth_daemon"
DAEMON = DAEMON_DIR + "/daemon"
KEY = DAEMON_DIR + "/secret.key"
SCRIPT = "/home/user/test_auth.sh"
REPORT = "/home/user/audit_report.log"
daemon_pid = int(os.environ["DAEMON_PID"])


def stop_daemon():
    global daemon_pid
    if not daemon_pid:
        return
    try:
        os.kill(daemon_pid, signal.SIGTERM)
    except ProcessLookupError:
        daemon_pid = 0
        return
    for _ in range(30):
        if not os.path.exists(f"/proc/{daemon_pid}"):
            daemon_pid = 0
            return
        time.sleep(0.05)
    try:
        os.kill(daemon_pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    daemon_pid = 0
    time.sleep(0.1)


def start_daemon():
    global daemon_pid
    p = subprocess.Popen(
        [DAEMON], cwd=DAEMON_DIR,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True,
    )
    daemon_pid = p.pid
    deadline = time.time() + 3
    while time.time() < deadline:
        if p.poll() is not None:
            pytest.fail(f"Makefile-built daemon exited with status {p.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 9000), timeout=0.1):
                pass
            break
        except OSError:
            time.sleep(0.05)
    else:
        pytest.fail("Makefile-built daemon did not listen on 127.0.0.1:9000")
    assert os.path.realpath(f"/proc/{daemon_pid}/exe") == os.path.realpath(DAEMON)


def replace_key():
    # Use unpredictable printable 16-byte keys, matching the supplied key's
    # shape while preventing a server from recognizing a fixed known token.
    alphabet = string.ascii_letters + string.digits
    data = "".join(secrets.choice(alphabet) for _ in range(16)).encode()
    with open(KEY, "wb") as f:
        f.write(data)
    os.chmod(KEY, 0o400)
    return data


def expected_token():
    with open(KEY, "rb") as f:
        key_bytes = f.read().strip()
    return "".join(f"{b ^ 0x7F:02x}" for b in key_bytes)


def request(cookie=None):
    with socket.create_connection(("127.0.0.1", 9000), timeout=2) as s:
        lines = ["GET / HTTP/1.1", "Host: 127.0.0.1", "Connection: close"]
        if cookie is not None:
            lines.append("Cookie: " + cookie)
        raw = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii")
        s.sendall(raw)
        s.settimeout(2)
        response = b""
        while b"\r\n" not in response:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
    assert response.startswith(b"HTTP/1.1 "), f"Invalid or missing HTTP response: {response!r}"
    return int(response.split(None, 2)[1])


def assert_daemon_alive():
    assert daemon_pid and os.path.exists(f"/proc/{daemon_pid}"), "Daemon is no longer running"
    assert os.path.realpath(f"/proc/{daemon_pid}/exe") == os.path.realpath(DAEMON)


def test_source_and_makefile_were_actually_used():
    source_path = DAEMON_DIR + "/daemon.c"
    makefile_path = DAEMON_DIR + "/Makefile"
    assert os.path.isfile(source_path)
    assert os.path.isfile(makefile_path)
    source = open(source_path, encoding="utf-8").read()
    makefile = open(makefile_path, encoding="utf-8").read()
    assert re.search(r"\bparse_cookie\s*\(", source), "daemon.c has no parse_cookie function"
    assert re.search(r"\bvalidate_token\s*\(", source), "daemon.c has no validate_token function"
    clean = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert not re.search(r"\breturn\s+1\s*;", clean), "validate_token remains hardcoded true"
    assert not re.search(r"strcpy\s*\(\s*token_out\s*,", clean), "Unsafe strcpy into token_out remains"
    assert not re.search(r"sscanf\s*\([^;]*[\"']%s[\"']", clean), "Unbounded sscanf %s remains"
    assert "daemon.c" in makefile, "Makefile does not build daemon.c"


def test_secret_key_permissions():
    assert os.path.isfile(KEY), f"{KEY} does not exist."
    permissions = stat.S_IMODE(os.stat(KEY).st_mode)
    assert permissions == 0o400, f"Permissions of {KEY} are not 0400. Got {oct(permissions)}."


def test_daemon_valid_token():
    # Restart against several verifier-generated keys. This defeats fixed-token
    # servers while preserving the required 16-byte key policy.
    for _ in range(4):
        replace_key()
        stop_daemon()
        start_daemon()
        assert request("auth_token=" + expected_token()) == 200
        assert_daemon_alive()


def test_daemon_invalid_token():
    valid = expected_token()
    invalids = [
        "badtoken",
        secrets.token_hex(16),
        valid[:-1],
        valid + "0",
        "g" * 32,
        "",
    ]
    for token in invalids:
        if token == valid:
            token = ("0" if token[0] != "0" else "1") + token[1:]
        assert request("auth_token=" + token) == 403
        assert_daemon_alive()
    assert request(None) == 403


def test_daemon_buffer_overflow_fix():
    for size in (200, 511, 700):
        massive_token = "A" * size
        assert request("auth_token=" + massive_token) == 403
        assert_daemon_alive()
    assert request("auth_token=" + expected_token()) == 200


def test_auth_script_exists_and_exercises_all_requests():
    global daemon_pid
    assert os.path.isfile(SCRIPT), f"Verification script not found at {SCRIPT}"
    token = expected_token()
    observed = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            cookie = self.headers.get("Cookie", "")
            observed.append(cookie)
            status = 200 if cookie == "auth_token=" + token else 403
            self.send_response(status)
            self.send_header("Content-Length", "2")
            self.end_headers()
            try:
                self.wfile.write(b"OK" if status == 200 else b"NO")
            except BrokenPipeError:
                pass
        def log_message(self, *args):
            pass

    stop_daemon()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 9000), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        try:
            os.unlink(REPORT)
        except FileNotFoundError:
            pass
        started = time.time()
        result = subprocess.run(["bash", SCRIPT], timeout=20, capture_output=True, text=True)
        assert result.returncode == 0, f"test_auth.sh failed: {result.stdout}\n{result.stderr}"
        assert os.path.isfile(REPORT), "test_auth.sh did not create audit_report.log"
        assert os.path.getmtime(REPORT) >= started - 1, "Audit report was not regenerated by test_auth.sh"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert "auth_token=" + token in observed, "test_auth.sh did not send the computed valid token"
    assert "auth_token=badtoken" in observed, "test_auth.sh did not send the required badtoken request"
    assert "auth_token=" + ("A" * 200) in observed, "test_auth.sh did not send the 200-byte crash-test token"

    start_daemon()
    assert request("auth_token=" + token) == 200


def test_audit_report():
    assert os.path.isfile(REPORT), f"Audit report not found at {REPORT}"
    with open(REPORT, "r") as f:
        content = f.read()

    # Preserve the original report assertions.
    assert re.search(r"PERMISSIONS:\s*0?400", content)
    assert re.search(r"CWE_FIXED:\s*CWE-1(20|19)", content)
    assert re.search(r"VALID_RESPONSE:\s*200", content)
    assert re.search(r"INVALID_RESPONSE:\s*403", content)
    assert re.search(r"CRASH_TEST:\s*SUCCESS", content)

    lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert len(lines) == 6, "Audit report must contain exactly the six required non-empty lines"
    patterns = [
        r"PERMISSIONS:\s*0?400",
        r"CWE_FIXED:\s*CWE-1(?:20|19)",
        r"VALID_RESPONSE:\s*200",
        r"INVALID_RESPONSE:\s*403",
        r"CRASH_TEST:\s*SUCCESS",
    ]
    # The format shown in the instruction contains five labeled result lines.
    # Accept a trailing newline but no unrelated non-empty report content.
    if len(lines) == 6:
        # Some scripts include one harmless heading; all required lines must
        # still appear exactly once and in the prescribed order after filtering.
        required = [line for line in lines if any(re.fullmatch(p, line) for p in patterns)]
        assert len(required) == 5
        assert all(re.fullmatch(p, line) for p, line in zip(patterns, required))

    assert_daemon_alive()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    reward=1
fi
