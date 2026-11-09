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
mkdir -p /logs/verifier

run_checks() (
    set -e
    cd /home/user/audiostreamer

    # Recover the expected token from the deleted tracked configuration rather
    # than trusting the response from the submitted server.
    TOKEN="$(python3 - <<'PY'
import re
import subprocess

commits = subprocess.check_output(
    ["git", "rev-list", "--all", "--", "config.h.backup"], text=True
).splitlines()
for commit in commits:
    try:
        contents = subprocess.check_output(
            ["git", "show", f"{commit}:config.h.backup"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        continue
    match = re.search(r'DEFAULT_AUTH_TOKEN\s+"([A-Za-z0-9]{16})"', contents)
    if match:
        print(match.group(1))
        break
else:
    raise SystemExit("Could not recover the 16-character token from Git history")
PY
)"
    test "${#TOKEN}" -eq 16

    # Preserve the original deployed-state assertions before replacing the
    # listener with a freshly built copy of the submitted C program.
    AUTH_TOKEN="$TOKEN" python3 - <<'PY'
import os
import requests

url = "http://127.0.0.1:8080/status"
headers = {"Authorization": "Bearer " + os.environ["AUTH_TOKEN"]}
try:
    response = requests.get(url, headers=headers, timeout=2.0)
except requests.exceptions.Timeout:
    raise AssertionError("Server request timed out; the timezone loop may remain")
except requests.exceptions.ConnectionError:
    raise AssertionError("Failed to connect to the deployed server on port 8080")

assert response.status_code == 200, (
    f"Expected status code 200, got {response.status_code}. Response: {response.text}"
)
try:
    data = response.json()
except ValueError:
    raise AssertionError(f"Expected JSON, got: {response.text}")
assert data.get("status") == "ok", f"Expected status ok, got {data.get('status')}"
assert data.get("timezone") == "Europe/Berlin", (
    f"Expected Europe/Berlin, got {data.get('timezone')}"
)
PY

    # Ensure the requested code paths still exist, then force a clean build.
    grep -Eq '^[[:space:]]*#include[[:space:]]*<pthread.h>' src/server.c
    grep -q 'pthread_create' src/server.c
    grep -q 'normalize_timestamp' src/server.c
    grep -q 'normalize_timestamp' src/time_utils.c
    rm -f ./server
    make
    test -x ./server
    python3 - <<'PY'
with open("server", "rb") as f:
    assert f.read(4) == b"\x7fELF", "make did not produce an ELF executable"
PY

    # Remove every process currently listening on TCP port 8080 so the tests
    # below necessarily exercise the freshly compiled artifact.
    python3 - <<'PY'
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
        if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
            inodes.add(fields[9])

victims = set()
for name in os.listdir("/proc"):
    if not name.isdigit() or int(name) == os.getpid():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        fds = os.listdir(fd_dir)
    except OSError:
        continue
    for fd in fds:
        try:
            target = os.readlink(f"{fd_dir}/{fd}")
        except OSError:
            continue
        if target.startswith("socket:[") and target[8:-1] in inodes:
            victims.add(int(name))
            break
for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.3)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY

    KEEP_SERVER=0
    SERVER_PID=""
    cleanup() {
        if [ "$KEEP_SERVER" -ne 1 ] && [ -n "$SERVER_PID" ]; then
            kill "$SERVER_PID" 2>/dev/null || true
        fi
    }
    trap cleanup EXIT

    AUTH_TOKEN="$TOKEN" SERVER_TZ="Europe/Berlin" ./server >/tmp/audiostreamer-verifier.log 2>&1 &
    SERVER_PID=$!

    # Wait briefly for the freshly compiled server to bind.
    READY=0
    for _ in $(seq 1 30); do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            cat /tmp/audiostreamer-verifier.log >&2 || true
            exit 1
        fi
        if python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(0.1)
try:
    s.connect(("127.0.0.1", 8080))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY
        then
            READY=1
            break
        fi
        sleep 0.1
    done
    test "$READY" -eq 1
    test "$(readlink -f "/proc/$SERVER_PID/exe")" = "$(readlink -f ./server)"

    AUTH_TOKEN="$TOKEN" python3 - <<'PY'
import concurrent.futures
import os
import secrets
import requests

url = "http://127.0.0.1:8080/status"
token = os.environ["AUTH_TOKEN"]

# Authentication must be independently enforced; a constant-response server
# must not pass.
for headers in ({}, {"Authorization": "Bearer " + secrets.token_hex(12)}):
    response = requests.get(url, headers=headers, timeout=2.0)
    assert response.status_code == 401, (
        f"Unauthenticated or invalid-token request returned {response.status_code}"
    )

def authenticated_request(_):
    response = requests.get(
        url,
        headers={"Authorization": "Bearer " + token},
        timeout=2.0,
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data.get("status") == "ok", data
    assert data.get("timezone") == "Europe/Berlin", data
    return True

# Concurrent repeated calls execute normalize_timestamp and expose the original
# non-terminating timezone loop while also checking server responsiveness.
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(authenticated_request, range(16)))
assert all(results)
PY

    # Leave the verified compiled server running, as required by the task.
    KEEP_SERVER=1
)

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
