#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import csv
import tempfile
import json
import pytest

ORACLE_PATH = "/app/legacy_reporter"
AGENT_SCRIPT = "/home/user/processor.py"
NUM_RUNS = 50

@pytest.fixture(scope="module")
def fuzzed_inputs():
    random.seed(42)
    inputs = []
    for _ in range(NUM_RUNS):
        num_rows = random.randint(5, 50)
        rows = []
        for i in range(1, num_rows + 1):
            rows.append({
                "txn_id": i,
                "user_id": random.randint(1, 5),
                "timestamp": random.randint(100000, 1000000),
                "amount": round(random.uniform(-100.0, 100.0), 2),
            })
        random.shuffle(rows)
        inputs.append(rows)
    return inputs

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence(fuzzed_inputs):
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_SCRIPT, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent submission is byte-identical to the legacy binary"

    cases = []
    try:
        # Derive every expected answer first while the oracle is available.
        for idx, rows in enumerate(fuzzed_inputs):
            with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as tmp:
                writer = csv.DictWriter(tmp, fieldnames=["txn_id", "user_id", "timestamp", "amount"])
                writer.writeheader()
                writer.writerows(rows)
                tmp_path = tmp.name

            oracle_proc = subprocess.run(
                [ORACLE_PATH, tmp_path],
                capture_output=True,
                text=True,
                check=False,
            )
            assert oracle_proc.returncode == 0, (
                f"Oracle failed on run {idx} with input:\n{rows}\n"
                f"Stderr: {oracle_proc.stderr}"
            )
            try:
                oracle_json = json.loads(oracle_proc.stdout)
            except json.JSONDecodeError:
                pytest.fail(f"Oracle output is not valid JSON on run {idx}: {oracle_proc.stdout}")
            cases.append((idx, rows, tmp_path, oracle_json))

        # The replacement must work independently; it may not forward requests to
        # the legacy executable during verification.
        os.remove(ORACLE_PATH)
        assert not os.path.exists(ORACLE_PATH)

        for idx, rows, tmp_path, oracle_json in cases:
            agent_proc = subprocess.run(
                ["python3", AGENT_SCRIPT, tmp_path],
                capture_output=True,
                text=True,
                check=False,
            )
            assert agent_proc.returncode == 0, (
                f"Agent script failed on run {idx} with input:\n{rows}\n"
                f"Stderr: {agent_proc.stderr}"
            )
            try:
                agent_json = json.loads(agent_proc.stdout)
            except json.JSONDecodeError:
                pytest.fail(f"Agent output is not valid JSON on run {idx}: {agent_proc.stdout}")

            assert oracle_json == agent_json, (
                f"Mismatch on run {idx}!\n"
                f"Input CSV rows:\n{rows}\n\n"
                f"Oracle Output:\n{oracle_json}\n\n"
                f"Agent Output:\n{agent_json}"
            )
    finally:
        for _, _, tmp_path, _ in cases:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
