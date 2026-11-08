#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import subprocess
import sys
import tempfile

import pytest

BASE_DIR = "/home/user/uptime_monitor"
SCRIPT_PATH = os.path.join(BASE_DIR, "calculator.py")
LOG_PATH = os.path.join(BASE_DIR, "health_logs.txt")
JSON_PATH = os.path.join(BASE_DIR, "final_metrics.json")


@pytest.fixture(scope="module", autouse=True)
def run_calculator():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd=BASE_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"calculator.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_final_metrics_exists():
    assert os.path.isfile(JSON_PATH), (
        f"File {JSON_PATH} does not exist. Did you run the script and generate the output?"
    )


def test_final_metrics_values():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."
    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} is missing."

    total_requests = 0
    error_requests = 0

    with open(LOG_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) < 3:
                continue

            total_requests += 1
            status_str = parts[2]

            if status_str == "TIMEOUT":
                error_requests += 1
            else:
                try:
                    status_code = int(status_str)
                    if status_code >= 500:
                        error_requests += 1
                except ValueError:
                    pass

    expected_uptime_pct = round((1 - (error_requests / total_requests)) * 100, 4) if total_requests > 0 else 0.0
    expected_burn_rate = round((error_requests / total_requests) / 0.001, 4) if total_requests > 0 else 0.0

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "total_requests" in data, "Key 'total_requests' is missing from the JSON output."
    assert data["total_requests"] == total_requests, \
        f"Expected total_requests to be {total_requests}, but got {data['total_requests']}."

    assert "error_requests" in data, "Key 'error_requests' is missing from the JSON output."
    assert data["error_requests"] == error_requests, \
        f"Expected error_requests to be {error_requests} (only 5xx and TIMEOUT count), but got {data['error_requests']}."

    assert "uptime_percentage" in data, "Key 'uptime_percentage' is missing from the JSON output."
    assert data["uptime_percentage"] == expected_uptime_pct, \
        f"Expected uptime_percentage to be {expected_uptime_pct}, but got {data['uptime_percentage']}."

    assert "burn_rate" in data, "Key 'burn_rate' is missing from the JSON output."
    assert data["burn_rate"] == expected_burn_rate, \
        f"Expected burn_rate to be {expected_burn_rate}, but got {data['burn_rate']}."


def test_process_logs_on_generated_inputs():
    spec = importlib.util.spec_from_file_location("submitted_calculator", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, "Could not import calculator.py."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "process_logs", None)), "calculator.py must define process_logs(filepath)."

    rng = random.SystemRandom()
    for case_number in range(3):
        statuses = (
            [str(rng.randint(200, 399)) for _ in range(rng.randint(3, 11))]
            + [str(rng.randint(400, 499)) for _ in range(rng.randint(2, 7))]
            + [str(rng.randint(500, 599)) for _ in range(rng.randint(1, 5))]
            + ["TIMEOUT" for _ in range(rng.randint(1, 4))]
        )
        rng.shuffle(statuses)

        with tempfile.NamedTemporaryFile(mode="w", delete=False) as log_file:
            temp_path = log_file.name
            for index, status in enumerate(statuses):
                latency = "-" if status == "TIMEOUT" else str(rng.randint(1, 250))
                log_file.write(f"2026-01-01T00:00:{index:02d}Z generated-service {status} {latency}\n")

        try:
            actual = module.process_logs(temp_path)
        finally:
            os.remove(temp_path)

        errors = sum(status == "TIMEOUT" or 500 <= int(status) <= 599 for status in statuses)
        total = len(statuses)
        error_rate = errors / total
        expected = {
            "total_requests": total,
            "error_requests": errors,
            "uptime_percentage": round((1 - error_rate) * 100, 4),
            "burn_rate": round(error_rate / 0.001, 4),
        }
        assert actual == expected, f"process_logs returned incorrect metrics for generated case {case_number + 1}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
