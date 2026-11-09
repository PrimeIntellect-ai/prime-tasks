#!/bin/bash
set -u
mkdir -p /logs/verifier

if (
    set -e
    cd /app/ticket-service

    BIN=/tmp/ticket-service-verified
    TESTFILE=$(mktemp -p /app/ticket-service verifier_XXXXXX_test.go)
    PID=""

    kill_listener() {
        python3 - <<'PY'
import os
import signal
import time

inodes = set()
for path in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(path) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].endswith(':1F90') and fields[3] == '0A':
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
    except OSError:
        pass

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
if pids:
    time.sleep(0.4)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
    }

    cleanup() {
        if [ -n "$PID" ]; then
            kill "$PID" 2>/dev/null || true
            wait "$PID" 2>/dev/null || true
        fi
        rm -f "$TESTFILE" "$BIN" /tmp/ticket-service-verifier.log /tmp/verify_ticket_http.py
        kill_listener >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    cat > "$TESTFILE" <<'GO_TEST'
package main

import (
    "testing"
    "time"
)

func TestVerifierParseDate(t *testing.T) {
    valid := map[string]time.Time{
        "2023/10/05 14:30:00": time.Date(2023, 10, 5, 14, 30, 0, 0, time.UTC),
        "2024/02/29 00:00:00": time.Date(2024, 2, 29, 0, 0, 0, 0, time.UTC),
        "1999/12/31 23:59:59": time.Date(1999, 12, 31, 23, 59, 59, 0, time.UTC),
    }
    for input, want := range valid {
        got, err := parseDate(input)
        if err != nil {
            t.Fatalf("parseDate rejected valid client date %q: %v", input, err)
        }
        if !got.Equal(want) {
            t.Fatalf("parseDate(%q) = %v, want %v", input, got, want)
        }
    }

    invalid := []string{
        "2023-10-05 14:30:00",
        "2023/10/05T14:30:00",
        "2023/02/29 14:30:00",
        "2023/10/05 24:00:00",
        "2023/10/05 14:30:00Z",
        "2023/10/05 14:30:00 trailing",
    }
    for _, input := range invalid {
        if _, err := parseDate(input); err == nil {
            t.Fatalf("parseDate incorrectly accepted %q", input)
        }
    }
}
GO_TEST

    # Exercise parser.go directly, then ensure the complete repaired application builds.
    go test parser.go "$TESTFILE"
    go build -o "$BIN" .

    cat > /tmp/verify_ticket_http.py <<'PY'
import datetime
import json
import secrets
import sys
import time
import urllib.error
import urllib.request

URL = "http://127.0.0.1:8080/auth"
CODE = "gamma ray burst"
mode = sys.argv[1]

def request(method="POST", payload=None, raw=None):
    if raw is not None:
        body = raw
    elif payload is not None:
        body = json.dumps(payload).encode()
    else:
        body = None
    req = urllib.request.Request(URL, data=body, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()

# Wait until the newly launched executable owns the endpoint.
last_error = None
for _ in range(30):
    try:
        status, body = request(payload={"ticket_date": "2023/10/05 14:30:00", "code": CODE})
        break
    except (OSError, urllib.error.URLError) as error:
        last_error = error
        time.sleep(0.1)
else:
    raise AssertionError(f"service did not start: {last_error}")

if mode == "wrong-key":
    assert status == 401, f"service authenticated with an incorrect API_KEY: {status} {body!r}"
    sys.exit(0)

# Preserve the original verifier's successful request and response assertions.
status, body = request(payload={"ticket_date": "2024/05/12 10:00:00", "code": CODE})
assert status == 200, f"expected HTTP 200, got {status}: {body!r}"
parsed = json.loads(body)
assert parsed.get("status") == "authenticated", parsed

# Also test the exact ticket request documented in the instruction.
status, body = request(payload={"ticket_date": "2023/10/05 14:30:00", "code": CODE})
assert status == 200, (status, body)
assert json.loads(body).get("status") == "authenticated"

# Exercise additional valid dates selected only when verification runs.
for _ in range(6):
    year = 2000 + secrets.randbelow(40)
    month = 1 + secrets.randbelow(12)
    day = 1 + secrets.randbelow(28)
    hour = secrets.randbelow(24)
    minute = secrets.randbelow(60)
    second = secrets.randbelow(60)
    value = datetime.datetime(year, month, day, hour, minute, second).strftime("%Y/%m/%d %H:%M:%S")
    status, body = request(payload={"ticket_date": value, "code": CODE})
    assert status == 200, f"valid date {value!r} was rejected: {status} {body!r}"
    assert json.loads(body).get("status") == "authenticated"

wrong_code = "wrong-" + secrets.token_hex(20)
status, body = request(payload={"ticket_date": "2023/10/05 14:30:00", "code": wrong_code})
assert status == 403, f"incorrect authorization code was not rejected: {status} {body!r}"

for bad_date in (
    "2023-10-05 14:30:00",
    "2023/02/29 14:30:00",
    "2023/10/05T14:30:00",
    "2023/10/05 14:30:00Z",
    "not a date",
):
    status, body = request(payload={"ticket_date": bad_date, "code": CODE})
    assert status == 400, f"invalid date {bad_date!r} was not rejected: {status} {body!r}"

status, body = request(method="GET")
assert status == 405, f"GET /auth should be rejected with 405, got {status}"
status, body = request(raw=b'{broken json')
assert status == 400, f"malformed JSON should be rejected with 400, got {status}"
PY

    kill_listener

    # A wrong environment key must not authenticate.
    API_KEY="verifier-wrong-$(date +%s%N)" "$BIN" >/tmp/ticket-service-verifier.log 2>&1 &
    PID=$!
    python3 /tmp/verify_ticket_http.py wrong-key
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    PID=""
    kill_listener

    # Run the artifact built from the submitted source with the recovered key.
    API_KEY="sec-99xyz-alpha" "$BIN" >/tmp/ticket-service-verifier.log 2>&1 &
    PID=$!
    python3 /tmp/verify_ticket_http.py correct
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
