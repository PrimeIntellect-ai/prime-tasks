#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone

import pytest

SCRIPT_PATH = "/home/user/metric_aggregator.py"
LOGS_PATH = "/home/user/ping_logs.jsonl"
METRICS_PATH = "/home/user/metrics.json"


def run_aggregator(input_path, output_path):
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing or is not a file."
    if os.path.exists(output_path):
        os.remove(output_path)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Aggregator exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(output_path), f"Aggregator did not create {output_path}."


def parse_iso_timestamp(value, entry_index):
    assert isinstance(value, str), (
        f"Entry {entry_index} 'timestamp' must be a string. "
        "Are datetime objects properly serialized?"
    )
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        pytest.fail(f"Entry {entry_index} timestamp is not valid ISO 8601: {value!r} ({exc})")


def validate_metrics(logs, metrics):
    assert isinstance(metrics, list), (
        f"Expected output to contain a JSON array, but got {type(metrics).__name__}."
    )
    assert len(metrics) == len(logs), (
        f"Expected {len(logs)} metric entries, found {len(metrics)}."
    )

    successful = 0
    total = 0
    latencies = []

    for i, (log, metric) in enumerate(zip(logs, metrics)):
        total += 1
        if log.get("status") == "success":
            successful += 1
        latencies.append(log.get("latency", 0))

        expected_uptime = successful / total
        window_size = 5
        window = latencies[-window_size:] if len(latencies) >= window_size else latencies
        expected_rolling_avg = sum(window) / len(window)

        assert isinstance(metric, dict), f"Entry {i} must be a JSON object."
        assert "timestamp" in metric, f"Entry {i} is missing the 'timestamp' key."
        actual_timestamp = parse_iso_timestamp(metric["timestamp"], i)
        expected_timestamp = parse_iso_timestamp(log["timestamp"], i)
        assert actual_timestamp == expected_timestamp, (
            f"Entry {i}: timestamp does not correspond to the input. "
            f"Expected {log['timestamp']!r}, got {metric['timestamp']!r}."
        )

        assert "cumulative_uptime" in metric, f"Entry {i} is missing the 'cumulative_uptime' key."
        assert isinstance(metric["cumulative_uptime"], (int, float)), (
            f"Entry {i} 'cumulative_uptime' must be a number."
        )

        assert "rolling_latency_avg" in metric, f"Entry {i} is missing the 'rolling_latency_avg' key."
        assert isinstance(metric["rolling_latency_avg"], (int, float)), (
            f"Entry {i} 'rolling_latency_avg' must be a number."
        )

        assert math.isclose(
            metric["cumulative_uptime"], expected_uptime, rel_tol=1e-5, abs_tol=1e-5
        ), (
            f"Entry {i}: Incorrect 'cumulative_uptime'. Expected {expected_uptime}, "
            f"got {metric['cumulative_uptime']}."
        )
        assert math.isclose(
            metric["rolling_latency_avg"], expected_rolling_avg, rel_tol=1e-5, abs_tol=1e-5
        ), (
            f"Entry {i}: Incorrect 'rolling_latency_avg'. Expected {expected_rolling_avg}, "
            f"got {metric['rolling_latency_avg']}. Check boundary conditions."
        )


@pytest.fixture(scope="session", autouse=True)
def execute_required_artifact():
    assert os.path.isfile(LOGS_PATH), f"{LOGS_PATH} is missing."
    run_aggregator(LOGS_PATH, METRICS_PATH)


def test_metrics_json_exists():
    """Verify that the metrics.json file was created successfully."""
    assert os.path.exists(METRICS_PATH), (
        f"{METRICS_PATH} does not exist. Did the script run and output the file?"
    )
    assert os.path.isfile(METRICS_PATH), f"{METRICS_PATH} is not a file."


def test_metrics_json_content():
    """Verify that metrics.json contains the correct calculated metrics."""
    assert os.path.isfile(LOGS_PATH), f"{LOGS_PATH} is missing."

    with open(LOGS_PATH, "r") as f:
        logs = [json.loads(line) for line in f if line.strip()]

    with open(METRICS_PATH, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{METRICS_PATH} does not contain valid JSON."

    validate_metrics(logs, metrics)


def test_aggregator_on_fresh_derived_input():
    """Execute the submitted script on fresh data to prevent a precomputed output."""
    rng = random.SystemRandom()
    base = datetime(2025, 2, 3, 8, 0, tzinfo=timezone.utc) + timedelta(
        minutes=rng.randrange(0, 10000)
    )
    statuses = ["failed", "success", "success", "failed", "success", "success", "failed", "success", "success"]
    logs = []
    for i, status in enumerate(statuses):
        logs.append({
            "timestamp": (base + timedelta(seconds=37 * i)).isoformat().replace("+00:00", "Z"),
            "status": status,
            "latency": rng.randrange(1, 500),
        })

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "fresh_ping_logs.jsonl")
        output_path = os.path.join(tmpdir, "fresh_metrics.json")
        with open(input_path, "w") as f:
            for log in logs:
                f.write(json.dumps(log) + "\n")

        run_aggregator(input_path, output_path)
        with open(output_path, "r") as f:
            try:
                metrics = json.load(f)
            except json.JSONDecodeError:
                assert False, f"{output_path} does not contain valid JSON."

        validate_metrics(logs, metrics)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
