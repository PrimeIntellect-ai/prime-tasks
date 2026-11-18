#!/bin/bash
set +e
mkdir -p /logs/verifier

cat > /tmp/verify_impl.sh <<'VERIFY_EOF'
#!/bin/bash
set -euo pipefail

REPO=/home/user/repo
TOKEN=TR4CK_M3_N0W
BASE_URL=http://127.0.0.1:9000

cd "$REPO"
test -f go.mod
test -f main.go
test -f wal.go
git rev-parse --is-inside-work-tree >/dev/null

# The regression commit must remain in history, ensuring the solution fixed it
# rather than checking out or reverting to a pre-regression snapshot.
BAD_COMMIT=$(git log --all --format='%H' --grep='^Refactor WAL read loop$' | head -n1)
test -n "$BAD_COMMIT"
git merge-base --is-ancestor "$BAD_COMMIT" HEAD
BAD_WAL=$(mktemp)
git show "$BAD_COMMIT:wal.go" > "$BAD_WAL"
if cmp -s "$BAD_WAL" wal.go; then
    echo 'wal.go is still identical to the regression commit' >&2
    exit 1
fi

# Exercise the submitted WAL implementation directly. Each incomplete record is
# derived in the test and must be ignored without losing the preceding record.
WAL_TEST_DIR=$(mktemp -d)
cp go.mod "$WAL_TEST_DIR/"
if test -f go.sum; then cp go.sum "$WAL_TEST_DIR/"; fi
cp ./*.go "$WAL_TEST_DIR/"
cat > "$WAL_TEST_DIR/verifier_wal_test.go" <<'GO_TEST_EOF'
package main

import (
    "bytes"
    "crypto/rand"
    "encoding/hex"
    "os"
    "path/filepath"
    "testing"
)

func verifierRecord(text string) []byte {
    b := bytes.Repeat([]byte{' '}, 100)
    copy(b, []byte(text))
    return b
}

func verifierRandomValue(t *testing.T) string {
    t.Helper()
    b := make([]byte, 12)
    if _, err := rand.Read(b); err != nil {
        t.Fatal(err)
    }
    return hex.EncodeToString(b)
}

func TestVerifierIgnoresEveryPartialTrailingRecord(t *testing.T) {
    expected := verifierRandomValue(t)
    complete := verifierRecord("stable=" + expected)
    trailing := verifierRecord("intruder=" + verifierRandomValue(t))

    for n := len("intruder="); n < len(trailing); n++ {
        name := filepath.Join(t.TempDir(), "partial.wal")
        contents := append(append([]byte{}, complete...), trailing[:n]...)
        if err := os.WriteFile(name, contents, 0600); err != nil {
            t.Fatal(err)
        }

        w := NewWAL(name)
        w.Replay()
        if got := w.Get("stable"); got != expected {
            t.Fatalf("partial length %d damaged complete record: got %q, want %q", n, got, expected)
        }
        if got := w.Get("intruder"); got != "" {
            t.Fatalf("partial length %d was replayed as a record: %q", n, got)
        }
        if len(w.data) != 1 {
            t.Fatalf("partial length %d produced unexpected entries: %#v", n, w.data)
        }
    }
}

func TestVerifierSkipsCorruptCompleteBlockAndContinues(t *testing.T) {
    expected := verifierRandomValue(t)
    corrupt := verifierRecord("this block has no key-value delimiter")
    valid := verifierRecord("survivor=" + expected)
    name := filepath.Join(t.TempDir(), "corrupt.wal")
    if err := os.WriteFile(name, append(corrupt, valid...), 0600); err != nil {
        t.Fatal(err)
    }

    w := NewWAL(name)
    w.Replay()
    if got := w.Get("survivor"); got != expected {
        t.Fatalf("valid record after corrupt block was not replayed: got %q, want %q", got, expected)
    }
    if len(w.data) != 1 {
        t.Fatalf("corrupt block produced unexpected entries: %#v", w.data)
    }
}
GO_TEST_EOF
(
    cd "$WAL_TEST_DIR"
    timeout 30s go test ./...
)

# Preserve the original requirement that the agent left a server running and
# that its health and fixed authenticated set/get round trip work.
cat > /tmp/check_agent_server.py <<'PY_EOF'
import time
import urllib.error
import urllib.parse
import urllib.request

base = "http://127.0.0.1:9000"
token = "TR4CK_M3_N0W"

def request(path, method="GET", auth=True, timeout=2):
    headers = {"Authorization": "Bearer " + token} if auth else {}
    req = urllib.request.Request(base + path, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8", "strict")

end = time.time() + 5
while True:
    try:
        status, _ = request("/health", auth=False, timeout=1)
        break
    except Exception:
        if time.time() >= end:
            raise AssertionError("Server is not reachable on 127.0.0.1:9000")
        time.sleep(0.25)
assert status == 200, status
status, _ = request("/set?key=test&val=123", method="POST")
assert status == 200, status
status, body = request("/get?key=test")
assert status == 200, status
assert body.strip() == "123", repr(body)
PY_EOF
python3 /tmp/check_agent_server.py

# Build the submitted Go program, replace any possible fake listener, and run
# that exact executable against a WAL containing a complete record followed by
# an incomplete record.
BIN=$(mktemp /tmp/kvstore-verifier.XXXXXX)
rm -f "$BIN"
go build -o "$BIN" .

test -x "$BIN"

python3 <<'PY_EOF'
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if int(fields[1].rsplit(':', 1)[1], 16) == 9000 and fields[3] == '0A':
            inodes.add(fields[9])

pids = set()
for entry in os.listdir('/proc'):
    if not entry.isdigit():
        continue
    try:
        for fd in os.listdir('/proc/' + entry + '/fd'):
            try:
                target = os.readlink('/proc/' + entry + '/fd/' + fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(entry))
    except OSError:
        pass
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.5)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY_EOF

RUNDIR=$(mktemp -d)
python3 - "$RUNDIR/data.wal" <<'PY_EOF'
import sys
record = bytearray(b' ' * 100)
record[:len(b'stable=expected')] = b'stable=expected'
with open(sys.argv[1], 'wb') as f:
    f.write(record)
    f.write(b'intruder=must_not_replay')
PY_EOF

(
    cd "$RUNDIR"
    ADMIN_TOKEN="$TOKEN" nohup "$BIN" >server.log 2>&1 &
    echo $! > server.pid
)
SERVER_PID=$(cat "$RUNDIR/server.pid")

cat > /tmp/check_built_server.py <<'PY_EOF'
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request

base = "http://127.0.0.1:9000"
token = "TR4CK_M3_N0W"

def request(path, method="GET", token_value=token, timeout=2):
    headers = {"Authorization": "Bearer " + token_value}
    req = urllib.request.Request(base + path, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", "strict")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")

end = time.time() + 8
while True:
    try:
        status, _ = request("/health")
        if status == 200:
            break
    except Exception:
        pass
    if time.time() >= end:
        raise AssertionError("built Go server did not start on 127.0.0.1:9000")
    time.sleep(0.2)

status, body = request("/get?key=stable")
assert status == 200, status
assert body == "expected", repr(body)
status, body = request("/get?key=intruder")
assert status == 200, status
assert body == "", "incomplete WAL record was replayed: " + repr(body)

key = "verify_" + secrets.token_hex(6)
value = secrets.token_hex(12)
query = urllib.parse.urlencode({"key": key, "val": value})
status, _ = request("/set?" + query, method="POST")
assert status == 200, status
status, body = request("/get?" + urllib.parse.urlencode({"key": key}))
assert status == 200, status
assert body == value, (body, value)

status, _ = request("/get?key=" + urllib.parse.quote(key), token_value="wrong-token")
assert status == 401, status
PY_EOF
python3 /tmp/check_built_server.py

kill -0 "$SERVER_PID"
test "$(readlink -f "/proc/$SERVER_PID/exe")" = "$(readlink -f "$BIN")"
VERIFY_EOF

chmod +x /tmp/verify_impl.sh
if /tmp/verify_impl.sh; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
