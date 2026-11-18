#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import json
import os
import random
import string
import subprocess
import time
import pytest

N_ITERATIONS = 500
AGENT_PATH = "/home/user/log_transformer.py"
LOCK_PATH = "/tmp/log_transformer.lock"


def generate_log_line():
    year = random.randint(2000, 2025)
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    hour = random.randint(0, 23)
    minute = random.randint(0, 59)
    second = random.randint(0, 59)
    level = random.choice(["INFO", "WARN", "ERROR", "DEBUG", "TRACE"])

    chars = string.ascii_letters + string.digits + " _:.-"
    payload_len = random.randint(5, 50)
    payload = "".join(random.choice(chars) for _ in range(payload_len))

    return f"{year:04d}-{month:02d}-{day:02d} {hour:02d}:{minute:02d}:{second:02d} [{level}] {payload}"


def generate_input():
    num_lines = random.randint(1, 50)
    return "\n".join(generate_log_line() for _ in range(num_lines)) + "\n"


def expected_output(test_input):
    transformed = []
    for raw_line in test_input.splitlines():
        parts = raw_line.strip().split(" ", 3)
        if len(parts) < 4:
            timestamp = "UNKNOWN"
            payload = raw_line.strip()
        else:
            timestamp = f"{parts[0]} {parts[1]}"
            payload = parts[3]

        transformed.append({
            "timestamp": timestamp,
            "payload": payload,
            "sha256_checksum": hashlib.sha256(raw_line.encode()).hexdigest(),
        })

    return json.dumps(transformed, indent=2) + "\n"


def agent_env():
    env = os.environ.copy()
    if "PYTHONPATH" in env:
        env["PYTHONPATH"] = f"/app/vendored_logparser:{env['PYTHONPATH']}"
    else:
        env["PYTHONPATH"] = "/app/vendored_logparser"
    return env


def test_locking_fixed():
    lock_file_path = '/app/vendored_logparser/vendored_logparser/locking.py'
    assert os.path.exists(lock_file_path), "locking.py is missing"

    with open(lock_file_path, 'r') as f:
        content = f.read()

    lines = content.splitlines()
    has_active_import = any(line.strip() == 'import fcntl' for line in lines)
    assert has_active_import, "The `import fcntl` statement is still commented out or missing in locking.py"


def test_agent_uses_required_lock():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"

    test_input = "2025-01-02 03:04:05 [INFO] lock contention test\n"
    lock_fd = open(LOCK_PATH, "a+")
    proc = None
    locked = False
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        locked = True
        proc = subprocess.Popen(
            ["python3", AGENT_PATH],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=agent_env(),
        )
        proc.stdin.write(test_input)
        proc.stdin.close()
        proc.stdin = None

        time.sleep(0.25)
        assert proc.poll() is None, "Agent did not block on /tmp/log_transformer.lock"

        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        locked = False
        stdout, stderr = proc.communicate(timeout=5)

        assert proc.returncode == 0, f"Agent failed after lock release:\n{stderr}"
        assert stdout == expected_output(test_input), "Incorrect output after lock contention"

        with open(LOCK_PATH, "a+") as probe:
            fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(probe, fcntl.LOCK_UN)
    finally:
        if locked:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.communicate()


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"

    env = agent_env()
    random.seed(42)

    for i in range(N_ITERATIONS):
        test_input = generate_input()
        expected = expected_output(test_input)

        agent_proc = subprocess.run(
            ["python3", AGENT_PATH],
            input=test_input,
            text=True,
            capture_output=True,
            env=env,
            timeout=10,
        )

        assert agent_proc.returncode == 0, (
            f"Agent script failed on iteration {i}. Stderr:\n{agent_proc.stderr}"
        )

        if agent_proc.stdout != expected:
            pytest.fail(
                f"Mismatch on iteration {i}.\n"
                f"Input:\n{test_input}\n"
                f"Expected:\n{expected}\n"
                f"Got:\n{agent_proc.stdout}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
