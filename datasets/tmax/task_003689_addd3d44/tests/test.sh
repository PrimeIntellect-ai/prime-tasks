#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import fcntl
import os
import random
import subprocess
import time
import pytest

ORACLE_PATH = "/tests/oracle_archiver"
AGENT_PATH = "/home/user/archiver/target/release/archiver"
LOCK_PATH = "/tmp/artifact.lock"

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}. Did you run 'cargo build --release'?"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable at {AGENT_PATH} is not executable."

def test_reference_available_and_not_copied():
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"
    with open(AGENT_PATH, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent executable must not be a byte-identical copy of the reference implementation"

def test_exclusive_lock_is_held_during_processing():
    input_data = bytes(range(256))
    oracle_proc = subprocess.run(
        [ORACLE_PATH],
        input=input_data,
        capture_output=True,
        check=False,
        timeout=5,
    )
    assert oracle_proc.returncode == 0, "Oracle failed during lock test"

    lock_fd = os.open(LOCK_PATH, os.O_RDWR | os.O_CREAT, 0o666)
    proc = subprocess.Popen(
        [AGENT_PATH],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        lock_observed = False
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
            except BlockingIOError:
                lock_observed = True
                break
            time.sleep(0.02)

        assert lock_observed, "Agent did not hold an exclusive flock on /tmp/artifact.lock while awaiting input"
        stdout, stderr = proc.communicate(input=input_data, timeout=5)
        assert proc.returncode == 0, f"Agent failed during lock test: {stderr.decode(errors='ignore')}"
        assert stdout == oracle_proc.stdout, "Agent output was incorrect during lock test"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.communicate()
        os.close(lock_fd)

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"

    random.seed(42)
    N = 100

    for i in range(N):
        length = random.randint(0, 8192)
        input_data = bytes(random.getrandbits(8) for _ in range(length))

        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            capture_output=True,
            check=False
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input of length {length}"
        oracle_out = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            capture_output=True,
            check=False
        )
        assert agent_proc.returncode == 0, f"Agent failed on input of length {length}. Stderr: {agent_proc.stderr.decode(errors='ignore')}"
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on random input of length {length}.\n"
                f"Expected {len(oracle_out)} bytes, got {len(agent_out)} bytes.\n"
                f"Oracle output (first 100 bytes): {oracle_out[:100]!r}\n"
                f"Agent output (first 100 bytes): {agent_out[:100]!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
