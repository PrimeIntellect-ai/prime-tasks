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
export PATH="/root/.cargo/bin:${PATH}"
ok=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import requests
import pytest

REPO = "/app/system-daemon"

def test_bad_commit_file_exists_and_valid():
    """Check that bad_commit.txt contains the actual regression-introducing commit."""
    bad_commit_path = "/home/user/bad_commit.txt"
    assert os.path.isfile(bad_commit_path), f"File {bad_commit_path} does not exist. You must write the bad commit hash to this file."

    with open(bad_commit_path, "r") as f:
        content = f.read().strip()

    assert re.match(r"^[0-9a-f]{40}$", content), f"File {bad_commit_path} does not contain a valid 40-character git commit hash. Found: {content}"

    commits = subprocess.check_output(
        ["git", "rev-list", "--reverse", "--first-parent", "v1.0.0..main", "--", "src/metrics.rs"],
        cwd=REPO,
        text=True,
    ).splitlines()
    assert commits, "Could not locate the metrics regression in repository history"
    expected = commits[0]

    bad_source = subprocess.check_output(
        ["git", "show", f"{expected}:src/metrics.rs"], cwd=REPO, text=True
    )
    parent_source = subprocess.check_output(
        ["git", "show", f"{expected}^:src/metrics.rs"], cwd=REPO, text=True
    )
    assert "std::ptr::null::<u8>().read()" in bad_source, "The identified historical commit is not the crashing metrics change"
    assert "std::ptr::null::<u8>().read()" not in parent_source, "The crash was already present before the identified commit"
    assert content == expected, f"Expected regression-introducing commit {expected}, found {content}"

def test_server_metrics_endpoint():
    """Check that the server is running and the metrics endpoint returns the correct response."""
    url = "http://127.0.0.1:8080/api/v1/metrics"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}. Is the server running in the background? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP status code 200, got {response.status_code}. Response: {response.text}"
    assert response.text.strip() == "Metrics OK", f"Expected response body 'Metrics OK', got '{response.text}'"
TEST_EOF

# Preserve the original checks against the server the agent left running.
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    ok=0
fi

# Build the submitted Rust source from scratch so a stale or unrelated server
# cannot substitute for a working fix.
rm -rf /tmp/verifier-target
if ! (cd /app/system-daemon && CARGO_TARGET_DIR=/tmp/verifier-target /root/.cargo/bin/cargo build); then
    ok=0
fi

binary=/tmp/verifier-target/debug/system-daemon
if [ ! -f "$binary" ] || [ ! -x "$binary" ]; then
    echo "Expected executable Rust artifact was not produced: $binary"
    ok=0
elif ! python3 - "$binary" <<'PY'
import sys
with open(sys.argv[1], 'rb') as f:
    assert f.read(4) == b'\x7fELF', "Built server is not an ELF executable"
PY
then
    ok=0
fi

# Stop whichever process owned port 8080, then exercise the freshly built
# submission itself on the required port.
python3 <<'PY'
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
                if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

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

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.5)
for pid in pids:
    try:
        os.kill(pid, 0)
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
PY

if [ -x "$binary" ]; then
    nohup "$binary" >/tmp/verifier-system-daemon.log 2>&1 &
    server_pid=$!
    ready=0
    for _ in $(seq 1 50); do
        if ! kill -0 "$server_pid" 2>/dev/null; then
            break
        fi
        if curl -fsS --max-time 1 http://127.0.0.1:8080/api/v1/metrics >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 0.1
    done
    if [ "$ready" -ne 1 ]; then
        echo "Freshly built server did not become ready"
        cat /tmp/verifier-system-daemon.log 2>/dev/null || true
        ok=0
    elif ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py::test_server_metrics_endpoint -x --tb=short 2>&1; then
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
