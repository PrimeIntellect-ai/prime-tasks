#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import math
import os
import random
import subprocess

import pytest

ANALYZER = "/home/user/analyzer.go"
RESULTS = "/home/user/results.json"
RAW_LOGS = "/home/user/data/raw_logs.txt"
BINARY = "/tmp/analyzer_submission"


def run_analyzer():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    subprocess.run([BINARY], cwd="/home/user", check=True, timeout=30)
    assert os.path.isfile(RESULTS), "Analyzer did not write /home/user/results.json"
    with open(RESULTS, "r") as f:
        return json.load(f)


def test_analyzer_go_exists():
    """Test that the Go program exists at the specified location."""
    assert os.path.exists(ANALYZER), f"Missing Go program: {ANALYZER}"
    assert os.path.isfile(ANALYZER), f"Expected a file, but found a directory: {ANALYZER}"


def test_analyzer_compiles_and_executes():
    subprocess.run(
        ["go", "build", "-o", BINARY, ANALYZER],
        cwd="/home/user",
        check=True,
        timeout=60,
        capture_output=True,
        text=True,
    )
    run_analyzer()


def test_results_json_exists_and_valid():
    """Test that the freshly generated results.json has the original expected values."""
    file_path = RESULTS
    assert os.path.exists(file_path), f"Missing results file: {file_path}"
    assert os.path.isfile(file_path), f"Expected a file, but found a directory: {file_path}"

    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {file_path} is not valid JSON.")

    required_keys = {"exact_mean", "bootstrap_mean", "ci_lower", "ci_upper", "reject_null"}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in results.json: {missing_keys}"

    exact_mean = data['exact_mean']
    assert isinstance(exact_mean, (int, float)), "exact_mean must be a number"
    assert abs(exact_mean - 1366.032) < 0.1, f"Exact mean incorrect. Expected ~1366.032, got: {exact_mean}"

    bootstrap_mean = data['bootstrap_mean']
    assert isinstance(bootstrap_mean, (int, float)), "bootstrap_mean must be a number"
    assert abs(bootstrap_mean - 1366.032) < 50, f"Bootstrap mean too far from exact mean. Got: {bootstrap_mean}"

    ci_lower = data['ci_lower']
    ci_upper = data['ci_upper']
    assert isinstance(ci_lower, (int, float)), "ci_lower must be a number"
    assert isinstance(ci_upper, (int, float)), "ci_upper must be a number"

    assert 400 < ci_lower < 900, f"ci_lower out of expected bounds (400, 900): {ci_lower}"
    assert 1800 < ci_upper < 2500, f"ci_upper out of expected bounds (1800, 2500): {ci_upper}"
    assert ci_lower < ci_upper, f"ci_lower ({ci_lower}) should be less than ci_upper ({ci_upper})"

    reject_null = data['reject_null']
    assert isinstance(reject_null, bool), "reject_null must be a boolean"
    expected_reject = ci_lower > 600
    assert reject_null == expected_reject, f"reject_null logic incorrect. Based on ci_lower ({ci_lower}), expected {expected_reject}, got {reject_null}"


def test_analyzer_processes_unseen_logs_and_bootstraps():
    """Exercise the submitted executable on verifier-generated data."""
    with open(RAW_LOGS, "rb") as f:
        original_logs = f.read()

    rng = random.SystemRandom()
    latency_ranges = [(40, 60), (70, 90), (100, 120), (130, 150), (160, 180), (190, 210)]
    latencies = [round(rng.uniform(lo, hi), 3) for lo, hi in latency_ranges]
    retries = [0, 1, 0, 1, 0, 1]
    levels = ["INFO", "WARN", "ERROR", "DEBUG", "CRITICAL", "TRACE"]

    valid_lines = []
    scores = []
    for i, (latency, retry, level) in enumerate(zip(latencies, retries, levels)):
        valid_lines.append(
            f"[2026-09-11T12:00:{i:02d}Z] [{level}] Processed request in {latency:.3f}ms with {retry} retries."
        )
        scores.append(latency * (retry + 1.5))

    # These superficially similar records must not be included by a strict parser.
    invalid_lines = [
        "[2026-09-11T12:01:00Z] [INFO] Processed request in 99999.0ms with 9 retries. EXTRA",
        "[2026-09-11T12:01:01Z] [INFO] Processed request in 88888.0ms with retries.",
        "[2026-09-11T12:01:02Z] [WARN] Processed request in 77777.0ms with 5 retries",
        "ordinary unrelated log text",
    ]

    shuffled_lines = valid_lines + invalid_lines
    rng.shuffle(shuffled_lines)
    dynamic_logs = ("\n".join(shuffled_lines) + "\n").encode()

    n = len(scores)
    exact_expected = sum(scores) / n
    all_bootstrap_means = sorted(
        sum(sample) / n for sample in itertools.product(scores, repeat=n)
    )
    lower_expected = all_bootstrap_means[int(0.025 * len(all_bootstrap_means))]
    upper_expected = all_bootstrap_means[int(0.975 * len(all_bootstrap_means))]
    score_range = max(scores) - min(scores)

    try:
        with open(RAW_LOGS, "wb") as f:
            f.write(dynamic_logs)
        data = run_analyzer()

        required_keys = {"exact_mean", "bootstrap_mean", "ci_lower", "ci_upper", "reject_null"}
        assert not (required_keys - set(data)), "Dynamic run produced an incomplete schema"

        for key in ("exact_mean", "bootstrap_mean", "ci_lower", "ci_upper"):
            assert isinstance(data[key], (int, float)) and not isinstance(data[key], bool)
            assert math.isfinite(data[key]), f"{key} must be finite"
        assert isinstance(data["reject_null"], bool)

        assert math.isclose(data["exact_mean"], exact_expected, rel_tol=1e-9, abs_tol=1e-7), (
            f"Analyzer did not parse/engineer the unseen records correctly: "
            f"expected {exact_expected}, got {data['exact_mean']}"
        )
        assert abs(data["bootstrap_mean"] - exact_expected) <= max(1.0, 0.03 * score_range), (
            "Bootstrap mean is inconsistent with the verifier-generated dataset"
        )
        ci_tolerance = max(2.0, 0.08 * score_range)
        assert abs(data["ci_lower"] - lower_expected) <= ci_tolerance, (
            f"ci_lower is inconsistent with bootstrap percentile sampling: "
            f"expected near {lower_expected}, got {data['ci_lower']}"
        )
        assert abs(data["ci_upper"] - upper_expected) <= ci_tolerance, (
            f"ci_upper is inconsistent with bootstrap percentile sampling: "
            f"expected near {upper_expected}, got {data['ci_upper']}"
        )
        assert data["ci_lower"] <= data["ci_upper"]
        assert data["reject_null"] == (data["ci_lower"] > 600)
        # Every valid generated score is below 600, so this dataset must not reject H0.
        assert data["reject_null"] is False
    finally:
        with open(RAW_LOGS, "wb") as f:
            f.write(original_logs)
        # Leave results.json corresponding to the original task input.
        if os.path.isfile(BINARY):
            run_analyzer()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
