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
ok=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import requests
import pytest
import uuid

REPO = "/home/user/source_repo"
SCRIPT = "/home/user/cron_task.sh"
METRICS = "/home/user/metrics_output.json"
URL = "http://127.0.0.1:7331/api/metrics"


def get_actual_commit_count():
    try:
        result = subprocess.run(
            ["git", "-C", REPO, "rev-list", "--count", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
        return int(result.stdout.strip())
    except Exception as e:
        pytest.fail(f"Could not get commit count from {REPO}: {e}")


def test_dashboard_source_exists():
    source = "/home/user/dashboard.cpp"
    assert os.path.isfile(source), f"Missing {source}"
    assert os.path.getsize(source) > 0, f"{source} is empty"


def test_crontab_installed():
    try:
        result = subprocess.run(
            ["crontab", "-l"], capture_output=True, text=True, check=True
        )
        assert "/home/user/cron_task.sh" in result.stdout, \
            "cron_task.sh is not installed in the crontab"
        assert "* * * * *" in result.stdout, \
            "cron_task.sh is not scheduled to run every minute"
        functional_lines = [
            line.strip() for line in result.stdout.splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        assert any(
            re.match(r"^\*\s+\*\s+\*\s+\*\s+\*\s+.*(?:^|\s)/home/user/cron_task\.sh(?:\s|$)", line)
            for line in functional_lines
        ), "No active every-minute crontab entry runs /home/user/cron_task.sh"
    except subprocess.CalledProcessError:
        pytest.fail("No crontab installed for the user.")


def test_cron_script_fixed_and_functional():
    assert os.path.isfile(SCRIPT), f"Missing {SCRIPT}"
    with open(SCRIPT, "r") as f:
        content = f.read()
    # Retain the original absolute-path assertions.
    assert "/home/user/source_repo" in content or "cd /home/user/source_repo" in content, \
        "cron_task.sh does not seem to use the absolute path for source_repo"
    assert "/home/user/metrics_output.json" in content, \
        "cron_task.sh does not seem to use the absolute path for metrics_output.json"

    # Change the repository so a hard-coded initial count cannot pass.
    marker = "verifier-" + uuid.uuid4().hex
    subprocess.run(
        ["git", "-C", REPO, "commit", "--allow-empty", "-m", marker],
        capture_output=True,
        text=True,
        check=True,
    )
    expected = get_actual_commit_count()

    # Approximate cron's sparse environment and remove PATH entirely. A script
    # using absolute commands, or explicitly establishing a safe PATH, still works.
    env = {"HOME": "/home/user", "LOGNAME": "user", "USER": "user", "PATH": ""}
    result = subprocess.run(
        ["/bin/sh", SCRIPT], cwd="/", env=env,
        capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, \
        f"cron_task.sh failed in a cron-like environment: {result.stderr}"
    assert os.path.isfile(METRICS), f"{SCRIPT} did not create {METRICS}"
    try:
        with open(METRICS, "r") as f:
            data = json.load(f)
    except Exception as e:
        pytest.fail(f"{METRICS} is not valid JSON: {e}")
    assert data == {"commits": expected}, \
        f"Expected {{'commits': {expected}}}, got {data!r}"


def test_api_unauthorized():
    try:
        response = requests.get(URL, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the dashboard backend at {URL}: {e}")
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized without token, got {response.status_code}"
    wrong = requests.get(
        URL, headers={"Authorization": "Bearer T0k3n_S3cr3t_wrong"}, timeout=2
    )
    assert wrong.status_code == 401, \
        f"Expected 401 with an incorrect token, got {wrong.status_code}"


def test_api_authorized_and_content():
    headers = {"Authorization": "Bearer T0k3n_S3cr3t"}
    try:
        response = requests.get(URL, headers=headers, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the dashboard backend at {URL}: {e}")
    assert response.status_code == 200, \
        f"Expected 200 OK with valid token, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response body is not valid JSON")
    assert "commits" in data, "JSON response missing 'commits' key"
    expected_commits = get_actual_commit_count()
    assert data["commits"] == expected_commits, \
        f"Expected {expected_commits} commits, but API returned {data['commits']}"
TEST_EOF

# First verify that the agent actually left a running daemon and that the cron
# artifact works behaviorally after an unpredictable repository change.
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    ok=0
fi

# Compile the submitted C++ source itself; this verifies that dashboard.cpp is
# a usable C++ implementation rather than an unrelated placeholder.
if [ "$ok" -eq 1 ]; then
    if ! g++ -O2 /home/user/dashboard.cpp -o /tmp/dashboard_submission -lpthread >/tmp/dashboard_compile.log 2>&1; then
        cat /tmp/dashboard_compile.log
        ok=0
    fi
fi

cat << 'KILL_EOF' > /tmp/kill_7331.py
import os
import signal
import time


def listener_inodes():
    found = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    parts = line.split()
                    local, state, inode = parts[1], parts[3], parts[9]
                    if local.rsplit(":", 1)[1].upper() == "1CA3" and state == "0A":
                        found.add(inode)
        except OSError:
            pass
    return found


def signal_owners(sig):
    targets = listener_inodes()
    if not targets:
        return
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in targets:
                    try:
                        os.kill(int(pid), sig)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except OSError:
            pass

signal_owners(signal.SIGTERM)
time.sleep(0.5)
signal_owners(signal.SIGKILL)
time.sleep(0.2)
KILL_EOF

cat << 'SOURCE_TEST_EOF' > /tmp/test_compiled_submission.py
import json
import secrets
import time
import requests

URL = "http://127.0.0.1:7331/api/metrics"
HEADERS = {"Authorization": "Bearer T0k3n_S3cr3t"}
METRICS = "/home/user/metrics_output.json"


def request_with_retry(headers):
    last = None
    for _ in range(30):
        try:
            return requests.get(URL, headers=headers, timeout=1)
        except requests.RequestException as e:
            last = e
            time.sleep(0.1)
    raise AssertionError(f"Compiled dashboard.cpp did not listen on 127.0.0.1:7331: {last}")


def test_compiled_source_behavior_and_live_file_reads():
    assert request_with_retry({}).status_code == 401
    assert request_with_retry({"Authorization": "Bearer invalid"}).status_code == 401

    for _ in range(2):
        payload = {
            "commits": secrets.randbelow(1_000_000_000) + 1000,
            "nonce": secrets.token_hex(24),
        }
        body = json.dumps(payload, separators=(",", ":")) + "\n"
        with open(METRICS, "w") as f:
            f.write(body)
        response = request_with_retry(HEADERS)
        assert response.status_code == 200
        assert response.headers.get("Content-Type", "").lower().startswith("application/json")
        assert response.text == body, \
            "Authorized response was not the current contents of metrics_output.json"

    missing = requests.get("http://127.0.0.1:7331/not-an-endpoint", timeout=2)
    assert missing.status_code == 404
SOURCE_TEST_EOF

server_pid=""
if [ "$ok" -eq 1 ]; then
    python3 /tmp/kill_7331.py
    /tmp/dashboard_submission >/tmp/dashboard_submission.log 2>&1 &
    server_pid=$!
    if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_compiled_submission.py -x --tb=short 2>&1; then
        cat /tmp/dashboard_submission.log
        ok=0
    fi
fi

if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
fi
python3 /tmp/kill_7331.py >/dev/null 2>&1 || true

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
