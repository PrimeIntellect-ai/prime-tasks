#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import subprocess
import sys

import pytest

TICKET_DIR = "/home/user/ticket"
DETECTOR_PATH = os.path.join(TICKET_DIR, "detector.py")
RESOLUTION_PATH = os.path.join(TICKET_DIR, "resolution.json")


def load_detector_class():
    assert os.path.isfile(DETECTOR_PATH), f"Missing {DETECTOR_PATH}"
    spec = importlib.util.spec_from_file_location("submitted_detector", DETECTOR_PATH)
    assert spec is not None and spec.loader is not None, "Unable to load detector.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "AnomalyDetector"), "detector.py must define AnomalyDetector"
    return module.AnomalyDetector


def reference_results(values):
    count = 0
    mean = 0.0
    m2 = 0.0
    decisions = []

    for value in values:
        count += 1
        delta = value - mean
        mean += delta / count
        delta2 = value - mean
        m2 += delta * delta2

        if count < 3:
            decisions.append(True)
        else:
            variance = m2 / count
            stddev = math.sqrt(variance)
            decisions.append(abs(value - mean) <= 3 * stddev)

    return decisions, count, mean, m2


def get_expected_results():
    log_a_path = os.path.join(TICKET_DIR, "service_a.log")
    assert os.path.isfile(log_a_path), f"Missing {log_a_path}"

    values = []
    with open(log_a_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 4 and parts[2] == "Sent:":
                values.append(float(parts[3]))

    assert len(values) > 0, "No values found in service_a.log"
    decisions, _, mean, _ = reference_results(values)
    accepted = sum(decisions)
    rejected = len(decisions) - accepted
    return accepted, rejected, round(mean, 4)


def test_detector_executes_correct_welford_algorithm():
    Detector = load_detector_class()
    detector = Detector()

    # Independent verifier-selected data exercises both Welford's M2 update and
    # the square root needed to turn variance into standard deviation.
    values = [50.0, 51.0, 49.0, 50.5, 48.5] * 8 + [1000.0, 49.5, 50.25]
    expected_decisions, expected_count, expected_mean, expected_m2 = reference_results(values)
    actual_decisions = [bool(detector.process(value)) for value in values]

    assert actual_decisions == expected_decisions, "AnomalyDetector returned incorrect accept/reject decisions"
    assert detector.count == expected_count, "AnomalyDetector count is incorrect"
    assert math.isclose(detector.mean, expected_mean, rel_tol=1e-12, abs_tol=1e-12), "AnomalyDetector mean is incorrect"
    assert math.isclose(detector.M2, expected_m2, rel_tol=1e-12, abs_tol=1e-9), "AnomalyDetector M2 calculation is incorrect"


def test_pipeline_is_run_and_resolution_is_correct():
    if os.path.exists(RESOLUTION_PATH):
        os.remove(RESOLUTION_PATH)

    completed = subprocess.run(
        [sys.executable, os.path.join(TICKET_DIR, "run_pipeline.py")],
        cwd=TICKET_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, f"run_pipeline.py failed: {completed.stderr}"
    assert os.path.isfile(RESOLUTION_PATH), f"Missing {RESOLUTION_PATH}. Did run_pipeline.py generate it?"

    with open(RESOLUTION_PATH, "r") as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESOLUTION_PATH} is not valid JSON")

    assert "accepted" in result, "Missing 'accepted' key in resolution.json"
    assert "rejected" in result, "Missing 'rejected' key in resolution.json"

    expected_accepted, expected_rejected, expected_mean = get_expected_results()
    assert result["accepted"] == expected_accepted, f"Expected {expected_accepted} accepted, got {result['accepted']}"
    assert result["rejected"] == expected_rejected, f"Expected {expected_rejected} rejected, got {result['rejected']}"
    assert result.get("final_mean") == expected_mean, f"Expected final mean {expected_mean}, got {result.get('final_mean')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
