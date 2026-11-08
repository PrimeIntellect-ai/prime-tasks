#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import importlib.util
import inspect
import json
import math
import os
from pathlib import Path
import secrets
import statistics
import subprocess
import sys

import pytest

AGGREGATOR_PATH = Path("/home/user/service/aggregator.py")
RUNNER_PATH = Path("/home/user/service/run_production.py")
OUTPUT_PATH = Path("/home/user/metrics_output.json")

EXPECTED_RUNNER = '''import asyncio
import json
from aggregator import MetricsAggregator

async def main():
    aggregator = MetricsAggregator()

    # Test fetch_data_with_retry (should return [] after retries are exhausted, not crash)
    result = await aggregator.fetch_data_with_retry("http://metrics-api.local", retries=3)
    if result != []:
        print("Error: Expected empty list after exhausting retries.")
        return

    # High precision float data prone to catastrophic cancellation in naive formulas
    # These represent large closely spaced values (e.g., timestamps or high-value financial ticks)
    dataset = [100000000.0, 100000000.1, 100000000.2]

    try:
        stdev = aggregator.compute_standard_deviation(dataset)
    except Exception as e:
        print(f"Error computing standard deviation: {e}")
        return

    output = {
        "status": "success",
        "retries_exhausted_gracefully": True,
        "standard_deviation": round(stdev, 5)
    }

    with open("/home/user/metrics_output.json", "w") as f:
        json.dump(output, f, indent=2)

    print("Production run complete. Output written to /home/user/metrics_output.json")

if __name__ == "__main__":
    asyncio.run(main())
'''


def load_aggregator_module():
    assert AGGREGATOR_PATH.is_file(), "aggregator.py is missing"
    assert not AGGREGATOR_PATH.is_symlink(), "aggregator.py must be a regular submitted source file"
    spec = importlib.util.spec_from_file_location("submitted_aggregator", AGGREGATOR_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_aggregator_can_be_imported_and_runner_is_unmodified():
    module = load_aggregator_module()
    assert hasattr(module, "MetricsAggregator")
    assert RUNNER_PATH.read_text() == EXPECTED_RUNNER, "Do not modify run_production.py"


def test_fetch_data_with_retry_really_exhausts_retries():
    module = load_aggregator_module()
    aggregator = module.MetricsAggregator()
    assert inspect.iscoroutinefunction(aggregator.fetch_data_with_retry)

    retries = 4 + secrets.randbelow(5)
    timeout_events = 0

    def tracer(frame, event, arg):
        nonlocal timeout_events
        if (
            event == "exception"
            and Path(frame.f_code.co_filename).resolve() == AGGREGATOR_PATH.resolve()
            and frame.f_code.co_name == "fetch_data_with_retry"
        ):
            exc_type = arg[0]
            if isinstance(exc_type, type) and issubclass(exc_type, asyncio.TimeoutError):
                timeout_events += 1
        return tracer

    async def exercise():
        return await asyncio.wait_for(
            aggregator.fetch_data_with_retry("http://runtime-generated.invalid", retries=retries),
            timeout=2.0,
        )

    old_trace = sys.gettrace()
    sys.settrace(tracer)
    try:
        result = asyncio.run(exercise())
    finally:
        sys.settrace(old_trace)

    assert result == [], "Exhausting retries must return an empty list"
    assert timeout_events >= retries, "The timeout path must actually retry until the retry budget is exhausted"
    assert asyncio.run(aggregator.fetch_data_with_retry("ignored", retries=0)) == []


def test_standard_deviation_is_stable_on_unseen_inputs():
    module = load_aggregator_module()
    aggregator = module.MetricsAggregator()

    assert aggregator.compute_standard_deviation([]) == 0.0
    assert aggregator.compute_standard_deviation([123.0]) == 0.0

    for _ in range(6):
        base = float(10 ** (8 + secrets.randbelow(5)))
        step = secrets.choice([0.05, 0.1, 0.25, 1.5])
        offsets = [secrets.randbelow(31) - 15 for _ in range(9 + secrets.randbelow(8))]
        if len(set(offsets)) < 2:
            offsets[-1] += 1
        values = [base + step * offset for offset in offsets]

        expected = statistics.stdev(values)
        actual = aggregator.compute_standard_deviation(values)
        assert isinstance(actual, (int, float)) and math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=2e-3, abs_tol=1e-7), (
            f"Numerically unstable standard deviation for generated input: "
            f"expected {expected}, got {actual}"
        )


def test_production_runner_generates_output():
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()

    completed = subprocess.run(
        [sys.executable, str(RUNNER_PATH)],
        cwd=str(RUNNER_PATH.parent),
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert OUTPUT_PATH.is_file(), "run_production.py did not generate metrics_output.json"


def test_metrics_output_exists():
    """Verify that the metrics_output.json file was successfully generated."""
    file_path = "/home/user/metrics_output.json"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist. Did you run run_production.py successfully?"


def test_metrics_output_content():
    """Verify that the metrics_output.json contains the correct data and computed standard deviation."""
    file_path = "/home/user/metrics_output.json"

    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {file_path} does not contain valid JSON.")

    assert data.get("status") == "success", "The 'status' field in the output JSON is not 'success'."
    assert data.get("retries_exhausted_gracefully") is True, "The 'retries_exhausted_gracefully' field should be True."

    dataset = [100000000.0, 100000000.1, 100000000.2]
    expected_stdev = round(statistics.stdev(dataset), 5)

    assert "standard_deviation" in data, "The 'standard_deviation' field is missing from the output JSON."

    actual_stdev = data["standard_deviation"]
    assert actual_stdev == expected_stdev, (
        f"The computed standard deviation is incorrect. "
        f"Expected {expected_stdev}, but got {actual_stdev}. "
        "Ensure you fixed the numerical instability bug in aggregator.py."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
