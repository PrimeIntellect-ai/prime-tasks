#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

SERVICE_PID=""
ORACLE_REAL="/app/bin/auth_oracle.verifier-real"
ORACLE="/app/bin/auth_oracle"
ORACLE_LOG="/tmp/auth_oracle_calls.jsonl"

cleanup() {
    if [ -n "$SERVICE_PID" ]; then
        kill "$SERVICE_PID" 2>/dev/null || true
        wait "$SERVICE_PID" 2>/dev/null || true
    fi
    if [ -e "$ORACLE_REAL" ]; then
        rm -f "$ORACLE"
        mv "$ORACLE_REAL" "$ORACLE"
    fi
}
trap cleanup EXIT

SERVER="/home/user/auth_service/server.py"
if [ ! -f "$SERVER" ] || [ -L "$SERVER" ]; then
    exit 0
fi
python3 -m py_compile "$SERVER" >/dev/null 2>&1 || exit 0

# Stop anything the agent left on the required port. The verifier then starts the
# submitted entrypoint itself, so an unrelated fabricated listener cannot pass.
python3 <<'PY'
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].rsplit(":", 1)[-1].upper() == "22B8" and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except OSError:
        pass

time.sleep(0.5)
PY

# Instrument the real oracle. This both preserves its behavior and proves that
# server.py invokes it with the exact two arguments supplied in each request.
if [ ! -x "$ORACLE" ] || [ -e "$ORACLE_REAL" ]; then
    exit 0
fi
mv "$ORACLE" "$ORACLE_REAL" || exit 0
cat > "$ORACLE" <<'PY'
#!/usr/bin/python3
import fcntl
import json
import os
import sys

with open("/tmp/auth_oracle_calls.jsonl", "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    f.write(json.dumps(sys.argv[1:]) + "\n")
    f.flush()
    os.fsync(f.fileno())
os.execv("/app/bin/auth_oracle.verifier-real",
         ["/app/bin/auth_oracle.verifier-real"] + sys.argv[1:])
PY
chmod 755 "$ORACLE" || exit 0
: > "$ORACLE_LOG"

# Obtain the documented-to-be-extracted key from the supplied dump rather than
# embedding a second trusted answer in the tests.
API_KEY=$(python3 - <<'PY'
import re
p = open('/home/user/crash.core', 'rb').read()
m = re.search(rb'sec_[A-Za-z0-9_]+', p)
if not m:
    raise SystemExit(1)
print(m.group().decode('ascii'))
PY
) || exit 0

cd /home/user/auth_service || exit 0
API_KEY="$API_KEY" python3 "$SERVER" >/tmp/auth_service_verifier.log 2>&1 &
SERVICE_PID=$!

# Wait for the verifier-started service to bind.
python3 - <<'PY' || exit 0
import socket
import time
for _ in range(50):
    try:
        with socket.create_connection(("127.0.0.1", 8888), timeout=0.1):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit(1)
PY

export TEST_API_KEY="$API_KEY"
cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import string

import pytest
import requests

URL = "http://127.0.0.1:8888/verify"
KEY = os.environ["TEST_API_KEY"]
LOG = "/tmp/auth_oracle_calls.jsonl"


def calls():
    with open(LOG) as f:
        return [json.loads(line) for line in f if line.strip()]


def post(username, token, key=KEY):
    headers = {"X-API-Key": key, "Content-Type": "application/json"}
    try:
        return requests.post(
            URL,
            headers=headers,
            json={"username": username, "token": token},
            timeout=5,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("The auth service is not running or not listening on 127.0.0.1:8888.")
    except requests.exceptions.Timeout:
        pytest.fail("The auth service timed out.")


def assert_request(username, token, expected_status):
    before = len(calls())
    response = post(username, token)
    assert response.status_code == expected_status, (
        f"Expected HTTP {expected_status} for {username!r}/{token!r}, "
        f"got {response.status_code}. Response: {response.text}"
    )
    after = calls()
    assert len(after) == before + 1, "Each authorized request must invoke auth_oracle exactly once"
    assert after[-1] == [username, token], (
        "server.py did not pass username and token to auth_oracle as two exact arguments: "
        f"expected {[username, token]!r}, got {after[-1]!r}"
    )


def test_auth_service_running_and_fixed():
    # Preserve the original regression assertion.
    assert_request("Valid Space", "abcdefghijklmnop", 200)


def test_auth_service_normal_username():
    # Preserve the original normal-input assertion.
    assert_request("AdminUser", "1234567890123456", 200)


def test_auth_service_invalid_auth():
    # Preserve the original invalid-key assertion and ensure rejected requests do
    # not reach the wrapped binary.
    before = len(calls())
    response = post("AdminUser", "1234567890123456", key="wrong_key")
    assert response.status_code in [401, 403], (
        f"Expected HTTP 401 or 403 for invalid API key, got {response.status_code}."
    )
    assert len(calls()) == before


def test_randomized_argument_boundaries_and_oracle_results():
    # Values are generated only after the agent has finished. Shell metacharacters
    # and varied whitespace expose splitting, quoting, and shell=True regressions.
    marker = secrets.token_hex(10)
    valid_token = secrets.token_urlsafe(12)[:16]
    assert len(valid_token) == 16
    usernames = [
        f"user {marker}",
        f"two  spaces {marker}",
        f"semi;colon $(printf {marker})",
        f"quote'and\"backslash\\ {marker}",
        f"tabs\tinside {marker}",
    ]
    for username in usernames:
        assert_request(username, valid_token, 200)

    # Expected outcomes are derived from the oracle contract, not a fixed request
    # list: nonempty username plus exactly 16 token characters succeeds.
    bad15 = ''.join(secrets.choice(string.ascii_letters) for _ in range(15))
    bad17 = ''.join(secrets.choice(string.ascii_letters) for _ in range(17))
    assert_request(f"bad token {marker}", bad15, 500)
    assert_request(f"bad token {marker}", bad17, 500)
    assert_request("", valid_token, 500)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
