#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import gzip
import json
import os
import secrets
import subprocess
import time

import pytest

SCRIPT_PATH = "/home/user/check_quota.sh"
LOG_PATH = "/home/user/warnings.log"
LOCK_PATH = "/home/user/warnings.lock"
DATA_PATH = "/home/user/quotas.json.gz"


@pytest.fixture(scope="session", autouse=True)
def restore_files_after_tests():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    log_existed = os.path.exists(LOG_PATH)
    original_log = None
    if log_existed:
        with open(LOG_PATH, "rb") as f:
            original_log = f.read()

    yield

    with open(DATA_PATH, "wb") as f:
        f.write(original_data)
    if log_existed:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
    elif os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_uses_flock():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "flock" in content, "Script does not contain 'flock' command."
    assert "warnings.lock" in content, "Script does not reference 'warnings.lock'."


def test_warnings_log_contents():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."

    # Compute expected users dynamically
    expected_users = set()
    try:
        with gzip.open(DATA_PATH, "rt") as f:
            data = json.load(f)
            for item in data:
                if item["used"] > 0.9 * item["limit"]:
                    expected_users.add(item["user"])
    except Exception as e:
        pytest.fail(f"Could not read {DATA_PATH} to compute expected users: {e}")

    # Read actual users
    with open(LOG_PATH, "r") as f:
        actual_users = set(line.strip() for line in f if line.strip())

    assert actual_users == expected_users, f"Expected users {expected_users}, but got {actual_users} in {LOG_PATH}."


def _wait_for_process(proc, timeout=15):
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        pytest.fail(f"Submitted script timed out. stdout={stdout!r}, stderr={stderr!r}")
    assert proc.returncode == 0, (
        f"Submitted script exited with {proc.returncode}. "
        f"stdout={stdout!r}, stderr={stderr!r}"
    )


def _read_log_lines():
    assert os.path.isfile(LOG_PATH), f"Script did not create {LOG_PATH}."
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def test_script_execution_append_and_concurrent_locking():
    # Generate inputs at verification time so a script cannot pass by hardcoding
    # the usernames from the image's original quota file.
    prefix = "quota_" + secrets.token_hex(8)
    data = []
    expected = []
    for i in range(120):
        user = f"{prefix}_{i}"
        limit = 1000 + 10 * i
        if i % 4 == 0:
            used = 9 * limit // 10       # exactly 90%, must be excluded
        elif i % 4 == 1:
            used = 9 * limit // 10 + 1   # strictly over, must be included
        elif i % 4 == 2:
            used = 9 * limit // 10 - 1   # below, must be excluded
        else:
            used = limit                 # over 90%, must be included
        data.append({"user": user, "used": used, "limit": limit})
        if used * 10 > 9 * limit:
            expected.append(user)

    with gzip.open(DATA_PATH, "wt", encoding="utf-8") as f:
        json.dump(data, f)

    with open(LOG_PATH, "w", encoding="utf-8"):
        pass

    # Hold the required lock externally. A correct script must remain blocked and
    # must not modify the log until this exclusive lock is released.
    lock_file = open(LOCK_PATH, "a+")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    proc = subprocess.Popen(
        [SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    time.sleep(1.0)
    was_blocked = proc.poll() is None
    lines_while_locked = _read_log_lines()
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    lock_file.close()
    _wait_for_process(proc)

    assert was_blocked, "Script completed while another process held warnings.lock."
    assert lines_while_locked == [], "Script wrote to warnings.log without obtaining the exclusive lock."
    assert collections.Counter(_read_log_lines()) == collections.Counter(expected), (
        "A direct execution did not append exactly the dynamically expected usernames."
    )

    # Start several invocations together. Each invocation must append one complete
    # copy of the expected usernames without losing or corrupting any lines.
    invocation_count = 8
    procs = [
        subprocess.Popen(
            [SCRIPT_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        for _ in range(invocation_count)
    ]
    deadline = time.monotonic() + 20
    for concurrent_proc in procs:
        remaining = max(0.1, deadline - time.monotonic())
        _wait_for_process(concurrent_proc, timeout=remaining)

    actual_lines = _read_log_lines()
    expected_counts = collections.Counter({u: invocation_count + 1 for u in expected})
    assert len(actual_lines) == len(expected) * (invocation_count + 1), (
        "Concurrent executions produced missing, extra, or malformed log lines."
    )
    assert collections.Counter(actual_lines) == expected_counts, (
        "Concurrent executions did not append exactly one username per qualifying user per invocation."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
