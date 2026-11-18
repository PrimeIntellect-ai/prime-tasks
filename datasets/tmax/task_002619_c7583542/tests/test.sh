#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -u
mkdir -p /logs/verifier
PASS=1
RUN_PID=""
WAL_BACKUP=""

fail() {
    echo "VERIFIER FAILURE: $*" >&2
    PASS=0
}

stop_app_servers() {
    for proc in /proc/[0-9]*; do
        [ -e "$proc/exe" ] || continue
        exe=$(readlink "$proc/exe" 2>/dev/null || true)
        case "$exe" in
            "/app/server"|"/app/server (deleted)")
                kill "${proc##*/}" 2>/dev/null || true
                ;;
        esac
    done
    sleep 1
}

# The requested source, WAL, and compiled executable must all be real files.
python3 - <<'PY' || PASS=0
import os, stat, sys
for path in ("/app/src/server.cpp", "/app/db.wal", "/app/server"):
    try:
        mode = os.lstat(path).st_mode
    except OSError as exc:
        print(f"Missing required artifact {path}: {exc}", file=sys.stderr)
        sys.exit(1)
    if not stat.S_ISREG(mode):
        print(f"Required artifact is not a regular file: {path}", file=sys.stderr)
        sys.exit(1)
if not os.access("/app/server", os.X_OK):
    print("/app/server is not executable", file=sys.stderr)
    sys.exit(1)
with open("/app/server", "rb") as f:
    if f.read(4) != b"\x7fELF":
        print("/app/server is not an ELF executable", file=sys.stderr)
        sys.exit(1)
PY

# Verify that exactly the corrupt WAL line was removed and all valid records remain.
python3 - <<'PY' || PASS=0
import sys
expected = [f"SET key{i}=value{i}" for i in range(1, 101)]
with open("/app/db.wal", "r", encoding="utf-8") as f:
    actual = f.read().splitlines()
if actual != expected:
    print("/app/db.wal does not contain exactly the 100 expected valid entries", file=sys.stderr)
    sys.exit(1)
PY

# Independently compile the submitted source with the required command and ensure
# the executable left by the agent was built from that source.
rm -f /tmp/server.verifier-build
if ! g++ -O2 -pthread /app/src/server.cpp -o /tmp/server.verifier-build >/tmp/verifier-g++.log 2>&1; then
    cat /tmp/verifier-g++.log >&2
    fail "The submitted server.cpp does not compile with the required command"
elif ! cmp -s /app/server /tmp/server.verifier-build; then
    fail "/app/server is not the executable produced from the submitted server.cpp"
fi

# Stop any prior instance and launch the actual submitted /app/server. A different
# process already occupying port 8080 will cause this process to exit and fail.
stop_app_servers
nohup /app/server >/tmp/verifier-server.log 2>&1 &
RUN_PID=$!
sleep 1
if ! kill -0 "$RUN_PID" 2>/dev/null; then
    cat /tmp/verifier-server.log >&2 || true
    fail "/app/server did not remain running"
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import pytest
import requests
import concurrent.futures

TOKEN = "SECRET_TOKEN_992"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}
BASE_URL = "http://127.0.0.1:8080"

def make_request(endpoint):
    try:
        if endpoint == "/query":
            response = requests.get(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=3)
        else:
            response = requests.post(f"{BASE_URL}{endpoint}", headers=HEADERS, timeout=3)
        return response.status_code, response.text
    except requests.exceptions.Timeout:
        return "TIMEOUT", "Request timed out, possible deadlock."
    except requests.exceptions.ConnectionError:
        return "CONNECTION_ERROR", "Failed to connect, is the server running?"
    except Exception as e:
        return "ERROR", str(e)

def test_server_running_and_no_deadlock():
    try:
        init_resp = requests.get(f"{BASE_URL}/query", headers=HEADERS, timeout=2)
        assert init_resp.status_code == 200, f"Initial request failed with status {init_resp.status_code}: {init_resp.text}"
        assert init_resp.text == "Query OK"
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not running on 127.0.0.1:8080 or refused connection.")
    except requests.exceptions.Timeout:
        pytest.fail("Initial request timed out. Server might be hanging.")

    update_resp = requests.post(f"{BASE_URL}/update", headers=HEADERS, timeout=2)
    assert update_resp.status_code == 200
    assert update_resp.text == "Update OK"

    endpoints = ["/query", "/update"] * 50
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        futures = {executor.submit(make_request, ep): ep for ep in endpoints}
        for future in concurrent.futures.as_completed(futures):
            results.append(future.result())

    failures = [r for r in results if r[0] != 200]
    if failures:
        error_summary = {}
        for status, msg in failures:
            error_summary[status] = error_summary.get(status, 0) + 1
        pytest.fail(f"Concurrent requests failed. Summary of errors: {error_summary}. First few errors: {failures[:5]}")

    for status, text in results:
        assert text in ("Query OK", "Update OK")

def test_authentication_and_routes_are_real():
    bad_headers = [
        {},
        {"Authorization": "Bearer WRONG_TOKEN"},
        {"Authorization": "SECRET_TOKEN_992"},
    ]
    for headers in bad_headers:
        q = requests.get(f"{BASE_URL}/query", headers=headers, timeout=2)
        u = requests.post(f"{BASE_URL}/update", headers=headers, timeout=2)
        assert q.status_code == 401
        assert u.status_code == 401

    assert requests.post(f"{BASE_URL}/query", headers=HEADERS, timeout=2).status_code != 200
    assert requests.get(f"{BASE_URL}/update", headers=HEADERS, timeout=2).status_code != 200
    assert requests.get(f"{BASE_URL}/not-an-endpoint", headers=HEADERS, timeout=2).status_code != 200
TEST_EOF

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    PASS=0
fi

# Confirm the executable really loads the WAL: with a corrupt record restored, it
# must take the original corruption failure path rather than serving requests.
if [ -n "$RUN_PID" ]; then
    kill "$RUN_PID" 2>/dev/null || true
    wait "$RUN_PID" 2>/dev/null || true
fi
WAL_BACKUP=/tmp/db.wal.verifier-backup
cp /app/db.wal "$WAL_BACKUP"
printf '%s\n' 'CORRUPT_ENTRY_verifier_probe' >> /app/db.wal
timeout 3s /app/server >/tmp/verifier-corrupt.out 2>/tmp/verifier-corrupt.err
CORRUPT_RC=$?
mv "$WAL_BACKUP" /app/db.wal
WAL_BACKUP=""
if [ "$CORRUPT_RC" -eq 0 ] || [ "$CORRUPT_RC" -eq 124 ]; then
    fail "/app/server did not reject a corrupt WAL record"
elif ! grep -q "Corrupt entry found" /tmp/verifier-corrupt.err; then
    fail "/app/server did not execute the expected WAL corruption check"
fi

# Leave the verified executable running against the restored clean WAL.
nohup /app/server >/tmp/verifier-final-server.log 2>&1 &
RUN_PID=$!
sleep 1
if ! kill -0 "$RUN_PID" 2>/dev/null; then
    cat /tmp/verifier-final-server.log >&2 || true
    fail "The verified /app/server could not be left running"
else
    FINAL_BODY=$(curl -sS --max-time 2 -H 'Authorization: Bearer SECRET_TOKEN_992' -w '\n%{http_code}' http://127.0.0.1:8080/query 2>/dev/null || true)
    FINAL_STATUS=${FINAL_BODY##*$'\n'}
    FINAL_TEXT=${FINAL_BODY%$'\n'*}
    if [ "$FINAL_STATUS" != "200" ] || [ "$FINAL_TEXT" != "Query OK" ]; then
        fail "The final /app/server process is not serving the expected endpoint"
    fi
fi

if [ "$PASS" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
