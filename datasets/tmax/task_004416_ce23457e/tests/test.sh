#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

AGENT_CPP = "/home/user/process_telemetry.cpp"
AGENT_BIN = "/home/user/process_telemetry"
ORACLE_BIN = "/tests/oracle_process_telemetry"
FINAL_CSV = "/home/user/final_telemetry.csv"

def test_agent_files_exist():
    assert os.path.exists(AGENT_CPP), f"Missing source file: {AGENT_CPP}"
    assert os.path.exists(AGENT_BIN), f"Missing executable: {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Executable is not executable: {AGENT_BIN}"

def test_final_telemetry_csv():
    assert os.path.exists(FINAL_CSV), f"Missing final output file: {FINAL_CSV}"
    with open(FINAL_CSV, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "1620000000,SensorAlpha,45.2",
        "1620000000,SensorBeta,12.0",
        "1620000000,SensorGamma,9.1",
        "1620000010,SensorAlpha,46.1",
        "1620000010,SensorBeta,11.8",
        "1620000010,SensorGamma,9.5"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, f"Final CSV content mismatch.\nExpected:\n{expected_lines}\nActual:\n{actual_lines}"

def generate_fuzz_input():
    charset = "0123456789.abc"
    num_lines = random.randint(10, 100)
    lines = []
    for _ in range(num_lines):
        # Mostly 4 columns, sometimes 3 or 5 to test validation
        num_cols = random.choices([3, 4, 5], weights=[10, 80, 10])[0]
        cols = []
        for _ in range(num_cols):
            col_len = random.randint(1, 10)
            col = "".join(random.choice(charset) for _ in range(col_len))
            cols.append(col)
        lines.append(",".join(cols))

    # Introduce some duplicates to test deduplication
    if lines:
        for _ in range(random.randint(0, 5)):
            lines.append(random.choice(lines))

    random.shuffle(lines)
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BIN), f"Oracle missing: {ORACLE_BIN}"
    assert os.path.exists(AGENT_BIN), f"Agent binary missing: {AGENT_BIN}"

    random.seed(42)
    num_iterations = 100

    for i in range(num_iterations):
        test_input = generate_fuzz_input()

        oracle_proc = subprocess.run(
            [ORACLE_BIN],
            input=test_input,
            text=True,
            capture_output=True
        )

        agent_proc = subprocess.run(
            [AGENT_BIN],
            input=test_input,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Return code mismatch on fuzz iteration {i}.\n"
            f"Input:\n{test_input}\n"
            f"Oracle return code: {oracle_proc.returncode}\n"
            f"Agent return code: {agent_proc.returncode}"
        )

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Stdout mismatch on fuzz iteration {i}.\n"
            f"Input:\n{test_input}\n"
            f"Oracle stdout:\n{oracle_proc.stdout}\n"
            f"Agent stdout:\n{agent_proc.stdout}"
        )

        assert agent_proc.stderr == oracle_proc.stderr, (
            f"Stderr mismatch on fuzz iteration {i}.\n"
            f"Input:\n{test_input}\n"
            f"Oracle stderr:\n{oracle_proc.stderr}\n"
            f"Agent stderr:\n{agent_proc.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
