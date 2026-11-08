#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import struct
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_aggregator"
AGENT_PATH = "/home/user/log_cleaner"
SOURCE_PATH = "/home/user/solution.c"
VERIFIED_PATH = "/tmp/verified_log_cleaner"


def generate_input(num_records):
    records = []
    ts_per_metric = {1: 1000000, 2: 1000000, 3: 1000000, 4: 1000000}

    for _ in range(num_records):
        metric_id = random.choice([1, 2, 3, 4])
        if random.random() < 0.2:
            ts = ts_per_metric[metric_id]
        else:
            ts_per_metric[metric_id] += random.randint(1, 5)
            ts = ts_per_metric[metric_id]

        is_retry = random.choice([0, 1, 2])
        value = random.uniform(-1000.0, 1000.0)
        records.append(struct.pack('<QIId', ts, metric_id, is_retry, value))

    return b''.join(records)


def compile_and_validate_submission():
    assert os.path.isfile(SOURCE_PATH) and not os.path.islink(SOURCE_PATH), \
        f"C source not found as a regular file at {SOURCE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent program not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH) and not os.path.islink(AGENT_PATH), \
        f"Agent program at {AGENT_PATH} must be a regular file, not a symlink"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program at {AGENT_PATH} is not executable"

    compile_proc = subprocess.run(
        ["gcc", "-O3", "-pthread", SOURCE_PATH, "-o", VERIFIED_PATH],
        capture_output=True,
        timeout=60,
    )
    assert compile_proc.returncode == 0, (
        "Submitted solution.c did not compile with the required command.\n"
        + compile_proc.stderr.decode("utf-8", errors="ignore")
    )

    with open(AGENT_PATH, "rb") as f:
        submitted_binary = f.read()
    with open(VERIFIED_PATH, "rb") as f:
        rebuilt_binary = f.read()
    with open(ORACLE_PATH, "rb") as f:
        oracle_binary = f.read()

    assert submitted_binary == rebuilt_binary, \
        "log_cleaner is not the executable produced from the submitted solution.c by the required command"
    assert submitted_binary != oracle_binary, \
        "log_cleaner must not be a byte-for-byte copy of the legacy executable"


def build_read_only_jail(binary_path):
    jail = tempfile.mkdtemp(prefix="log_cleaner_jail_")
    os.chmod(jail, 0o755)

    jailed_binary = os.path.join(jail, "bin", "log_cleaner")
    os.makedirs(os.path.dirname(jailed_binary), exist_ok=True)
    shutil.copy2(binary_path, jailed_binary)

    ldd_proc = subprocess.run(["ldd", binary_path], capture_output=True, text=True, timeout=10)
    assert ldd_proc.returncode == 0, f"Unable to inspect rebuilt executable: {ldd_proc.stderr}"

    dependencies = set(re.findall(r'(/[^\s()]+)', ldd_proc.stdout))
    for dependency in dependencies:
        if not os.path.isfile(dependency):
            continue
        destination = os.path.join(jail, dependency.lstrip('/'))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(dependency, destination)

    for root, dirs, files in os.walk(jail):
        os.chmod(root, 0o555)
        for name in dirs:
            os.chmod(os.path.join(root, name), 0o555)
        for name in files:
            os.chmod(os.path.join(root, name), 0o555)

    return jail


def test_fuzz_equivalence():
    compile_and_validate_submission()
    jail = build_read_only_jail(VERIFIED_PATH)

    try:
        random.seed(42)
        for i in range(100):
            num_records = random.randint(10, 5000)
            input_data = generate_input(num_records)

            oracle_proc = subprocess.run(
                [ORACLE_PATH], input=input_data, capture_output=True, timeout=20
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"

            # Run the executable rebuilt from solution.c as an unprivileged user in
            # an isolated, read-only filesystem. The legacy executable and any
            # agent-created copies or wrappers are unavailable inside this jail.
            agent_proc = subprocess.run(
                ["chroot", "--userspec=65534:65534", jail, "/bin/log_cleaner"],
                input=input_data,
                capture_output=True,
                timeout=20,
            )
            assert agent_proc.returncode == 0, (
                f"Agent program failed on iteration {i} with return code "
                f"{agent_proc.returncode}. Stderr: "
                f"{agent_proc.stderr.decode('utf-8', errors='ignore')}"
            )

            if oracle_proc.stdout != agent_proc.stdout:
                pytest.fail(
                    f"Output mismatch on fuzz iteration {i} with {num_records} records.\n"
                    f"Oracle output length: {len(oracle_proc.stdout)} bytes\n"
                    f"Agent output length: {len(agent_proc.stdout)} bytes\n"
                    "The agent's output does not exactly match the legacy binary's output."
                )
    finally:
        os.chmod(jail, 0o755)
        shutil.rmtree(jail, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
