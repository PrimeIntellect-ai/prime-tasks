#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import time
import fcntl
import string
import random
import subprocess
from pathlib import Path
import pytest

AGENT_SCRIPT = "/home/user/project_tool.py"
ORACLE_SCRIPT = "/tests/project_tool_oracle.py"

def generate_fuzz_input(num_lines=100):
    lines = []
    chars = string.ascii_letters + string.digits + " \t,."
    for _ in range(num_lines):
        length = random.randint(0, 200)
        line = "".join(random.choices(chars, k=length))

        # Insert ALPHA and BETA
        if random.random() < 0.5 and length > 5:
            pos = random.randint(0, len(line) - 5)
            line = line[:pos] + "ALPHA" + line[pos+5:]
        if random.random() < 0.5 and len(line) > 4:
            pos = random.randint(0, len(line) - 4)
            line = line[:pos] + "BETA" + line[pos+4:]

        if random.random() < 0.3:
            line += ";"

        lines.append(line)
    return "\n".join(lines) + "\n"

def test_agent_script_exists():
    assert Path(AGENT_SCRIPT).exists(), f"Agent script {AGENT_SCRIPT} does not exist."
    assert Path(AGENT_SCRIPT).is_file(), f"{AGENT_SCRIPT} is not a file."

def test_fuzz_equivalence():
    """Fuzz equivalence test against the oracle."""
    random.seed(42)

    # We do 100 iterations of 100 lines each to simulate 10000 lines efficiently
    for i in range(100):
        test_input = generate_fuzz_input(100)

        oracle_proc = subprocess.run(
            [sys.executable, ORACLE_SCRIPT],
            input=test_input,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_output = oracle_proc.stdout

        agent_proc = subprocess.run(
            [sys.executable, AGENT_SCRIPT],
            input=test_input,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent script failed with error:\n{agent_proc.stderr}"

        if agent_proc.stdout != oracle_output:
            pytest.fail(
                f"Mismatch on fuzz iteration {i}.\n"
                f"Input:\n{test_input}\n"
                f"Expected (Oracle):\n{oracle_output}\n"
                f"Got (Agent):\n{agent_proc.stdout}"
            )

def test_search_flag(tmp_path):
    """Test the --search flag functionality."""
    target_dir = tmp_path / "search_target"
    target_dir.mkdir()

    # Create some files
    log1 = target_dir / "a.log"
    log1.write_text("log1")

    log2 = target_dir / "b.log"
    log2.write_text("log2")

    txt1 = target_dir / "c.txt"
    txt1.write_text("txt1")

    old_log = target_dir / "old.log"
    old_log.write_text("old")
    # Set mtime to 3 days ago
    old_time = time.time() - (3 * 24 * 3600)
    os.utime(old_log, (old_time, old_time))

    oracle_proc = subprocess.run(
        [sys.executable, ORACLE_SCRIPT, "--search", str(target_dir)],
        text=True,
        capture_output=True,
        check=True
    )
    oracle_output = oracle_proc.stdout

    agent_proc = subprocess.run(
        [sys.executable, AGENT_SCRIPT, "--search", str(target_dir)],
        text=True,
        capture_output=True
    )

    assert agent_proc.returncode == 0, f"Agent script --search failed:\n{agent_proc.stderr}"
    assert agent_proc.stdout == oracle_output, f"Mismatch in --search output.\nExpected:\n{oracle_output}\nGot:\n{agent_proc.stdout}"

def test_lockfile_flag(tmp_path):
    """Test the --lockfile flag functionality."""
    lock_path = tmp_path / "test.lock"

    # We will spawn the agent script in the background, making it wait for stdin
    agent_proc = subprocess.Popen(
        [sys.executable, AGENT_SCRIPT, "--lockfile", str(lock_path)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    time.sleep(0.5) # Give it time to start and acquire the lock

    # Try to acquire the lock ourselves
    fd = os.open(str(lock_path), os.O_RDWR | os.O_CREAT)
    try:
        # This should fail if the agent holds the lock
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        pytest.fail("Agent did not acquire an exclusive lock on the lockfile.")
    except BlockingIOError:
        pass # Expected

    # Close agent
    agent_proc.stdin.close()
    agent_proc.wait(timeout=2)

    # Now we should be able to acquire the lock
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(fd, fcntl.LOCK_UN)
    except BlockingIOError:
        pytest.fail("Agent did not release the lockfile upon exiting.")
    finally:
        os.close(fd)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
