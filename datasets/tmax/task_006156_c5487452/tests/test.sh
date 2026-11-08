#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
import uuid

import pytest


def test_mre_txt_content():
    path = "/home/user/mre.txt"
    assert os.path.isfile(path), f"File {path} is missing. You need to create it with the isolated input."

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_line = "TXN_003,1000.0,0.1;0.1;0.1,0.3"
    assert content == expected_line, f"Content of {path} is incorrect. Expected exactly the line causing the crash."


def test_aggregate_py_fixed():
    path = "/home/user/aggregate.py"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, 'r') as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "1e-9" in content or "0.000000001" in content, f"The script {path} does not seem to use the 1e-9 threshold as requested."
    assert "abs(" in content, f"The script {path} does not seem to use absolute value for the threshold check."


def test_report_json_generated_and_correct():
    path = "/home/user/report.json"
    assert os.path.isfile(path), f"File {path} is missing. Did you run the fixed script?"

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    expected_data = {
        "TXN_001": 7500.0,
        "TXN_002": "SKIPPED_ZERO",
        "TXN_003": "SKIPPED_ZERO",
        "TXN_004": 6000.0
    }

    assert data == expected_data, f"Content of {path} does not match the expected results."


def test_transactions_wal_unmodified():
    path = "/home/user/transactions.wal"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_content = """TXN_001,1500.0,0.5;0.5,0.8
TXN_002,2000.0,0.5;0.5,1.0
TXN_003,1000.0,0.1;0.1;0.1,0.3
TXN_004,3000.0,0.2;0.4,0.1"""

    assert content == expected_content, f"File {path} was modified, which violates the constraints."


def _expected_for(lines):
    expected = {}
    for line in lines:
        parts = line.split(',')
        txn_id = parts[0]
        amount = float(parts[1])
        components = [float(x) for x in parts[2].split(';')]
        discount = float(parts[3])
        denominator = sum(components) - discount
        if abs(denominator) < 1e-9:
            expected[txn_id] = "SKIPPED_ZERO"
        else:
            ratio = amount / denominator
            assert abs(ratio) <= 1000000
            expected[txn_id] = round(ratio, 4)
    return expected


def test_aggregate_behavior_and_execution():
    script = "/home/user/aggregate.py"
    report = "/home/user/report.json"
    wal = "/home/user/transactions.wal"

    assert os.path.isfile(script), f"File {script} is missing."
    with open(report, 'rb') as f:
        original_report = f.read()
    with open(wal, 'rb') as f:
        original_wal = f.read()

    prefix = uuid.uuid4().hex
    records = [
        f"{prefix}_NEAR_POS,0.000001,1.0000000005,1.0",
        f"{prefix}_NEAR_NEG,0.000001,0.9999999995,1.0",
        f"{prefix}_EXACT_ZERO,7.0,0.25;0.75,1.0",
        f"{prefix}_BOUND_POS,0.000001,1e-9,0.0",
        f"{prefix}_BOUND_NEG,0.000001,-1e-9,0.0",
        f"{prefix}_NORMAL,12.5,0.75,0.25",
    ]
    random.SystemRandom().shuffle(records)
    expected = _expected_for(records)

    fd, temp_wal = tempfile.mkstemp(prefix="behavior_", suffix=".wal")
    try:
        with os.fdopen(fd, 'w') as f:
            f.write('\n'.join(records) + '\n')

        if os.path.exists(report):
            os.remove(report)
        completed = subprocess.run(
            ["python3", script, temp_wal],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert completed.returncode == 0, (
            "The fixed aggregate.py failed when executed on precision edge cases.\n"
            f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
        )
        assert os.path.isfile(report), "Executing aggregate.py did not generate /home/user/report.json."
        with open(report, 'r') as f:
            try:
                generated = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("aggregate.py generated an invalid JSON report during behavioral testing.")

        assert generated == expected, (
            "aggregate.py does not implement the required abs(denominator) < 1e-9 behavior."
        )
        with open(wal, 'rb') as f:
            assert f.read() == original_wal, "aggregate.py modified /home/user/transactions.wal."
    finally:
        if os.path.exists(temp_wal):
            os.unlink(temp_wal)
        with open(report, 'wb') as f:
            f.write(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
