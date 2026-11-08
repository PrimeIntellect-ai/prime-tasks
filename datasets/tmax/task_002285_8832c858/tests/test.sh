#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import subprocess
import time
import uuid

import pytest
import requests


def test_regression_test_script_exists_and_runs():
    script_path = '/home/user/log_pipeline/regression_test.py'
    assert os.path.isfile(script_path), f"Expected regression test script at {script_path} is missing."
    assert os.path.getsize(script_path) > 0, "Regression test script is empty."

    with open(script_path, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=script_path)
    except SyntaxError as e:
        pytest.fail(f"Regression test script is not valid Python: {e}")

    assert any(isinstance(node, ast.Assert) for node in ast.walk(tree)), (
        "Regression test script must contain an assertion checking its results."
    )

    try:
        result = subprocess.run(
            ['python3', script_path],
            cwd='/home/user/log_pipeline',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Regression test script did not finish within 30 seconds.")

    assert result.returncode == 0, (
        f"Regression test script failed with exit code {result.returncode}:\n{result.stdout}"
    )


def test_pipeline_accuracy():
    """
    Tests the end-to-end log processing pipeline by pushing 10,000 log events
    with varied millisecond timestamps and verifying every calculated latency.
    """
    payload = []
    expected = {}
    run_id = str(uuid.uuid4())
    total_expected = 10000

    for i in range(total_expected):
        req_id = f"req-{run_id}-{i}"
        start_ts = 1700000000000 + secrets.randbelow(500000000) + i

        # Include both ordinary, unpredictable latencies and values larger than
        # the signed int32 range so timestamp arithmetic must use a safe type.
        if i % 4 == 0:
            latency = (1 << 31) + 1 + secrets.randbelow(1000000)
        else:
            latency = 1 + secrets.randbelow(2000000)

        expected[req_id] = latency
        payload.append({
            "id": req_id,
            "start_ts": start_ts,
            "end_ts": start_ts + latency,
        })

    try:
        response = requests.post("http://127.0.0.1:5000/logs", json=payload, timeout=10)
        response.raise_for_status()
    except Exception as e:
        pytest.fail(f"Failed to post logs to API: {e}. Is the Flask app running?")

    time.sleep(3)

    output_file = "/home/user/log_pipeline/output/metrics.json"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist. Did the worker run?"

    try:
        with open(output_file, "r") as f:
            lines = f.readlines()

        correct = 0
        seen = set()
        for line in lines:
            if not line.strip():
                continue
            data = json.loads(line)
            req_id = data.get("id")
            if req_id in expected:
                assert req_id not in seen, f"Duplicate output record for {req_id}"
                seen.add(req_id)
                if data.get("latency") == expected[req_id]:
                    correct += 1

        accuracy = correct / float(total_expected)
        assert accuracy == 1.0, (
            f"Accuracy metric is {accuracy} ({correct}/{total_expected} correct), "
            f"expected exactly 1.0. The worker is likely still suffering from integer "
            f"overflow or dropping records."
        )
    except AssertionError:
        raise
    except Exception as e:
        pytest.fail(f"Error evaluating metric from {output_file}: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
