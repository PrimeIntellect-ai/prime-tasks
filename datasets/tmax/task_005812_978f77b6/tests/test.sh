#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import importlib.util
import json
import os
import re
import secrets
import subprocess

import numpy as np
import pytest

REPORT_PATH = "/home/user/report.json"
SCORE_PATH = "/home/user/analytics/score.py"
REPO_PATH = "/home/user/analytics"


def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."


def test_report_contents():
    with open(REPORT_PATH, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")

    # Check db_password
    assert "db_password" in report_data, "Key 'db_password' is missing from the report."
    assert report_data["db_password"] == "pA55w0rd_xyz789", (
        f"Expected db_password to be 'pA55w0rd_xyz789', got '{report_data['db_password']}'"
    )

    # Check softmax_first_value
    assert "softmax_first_value" in report_data, "Key 'softmax_first_value' is missing from the report."

    # The true value is exp(1000) / (exp(1000)+exp(1001)+exp(1002))
    # = 1 / (1 + e + e^2), rounded to 4 decimal places: 0.0900
    expected_value = 0.0900
    actual_value = report_data["softmax_first_value"]

    assert isinstance(actual_value, (int, float)), "softmax_first_value must be a number."
    assert abs(actual_value - expected_value) < 1e-4, (
        f"Expected softmax_first_value to be {expected_value}, got {actual_value}"
    )

    assert set(report_data) == {"db_password", "softmax_first_value"}, (
        "The report must contain exactly the required two keys."
    )
    raw = open(REPORT_PATH, "r").read()
    value_match = re.search(
        r'"softmax_first_value"\s*:\s*(-?\d+\.\d{4})(?=\s*[,}])', raw
    )
    assert value_match, "softmax_first_value must be written with exactly 4 decimal places."


def test_password_is_present_in_git_history():
    history = subprocess.run(
        ["git", "log", "--all", "-p", "--"],
        cwd=REPO_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert history.returncode == 0, f"Could not inspect git history: {history.stderr}"
    assignments = re.findall(
        r'^\+?\s*DB_PASS\s*=\s*[\"\']([^\"\']+)[\"\']\s*$',
        history.stdout,
        flags=re.MULTILINE,
    )
    with open(REPORT_PATH, "r") as f:
        report_data = json.load(f)
    assert report_data["db_password"] in assignments, (
        "The reported password was not recovered from a DB_PASS assignment in git history."
    )


def load_score_module():
    assert os.path.isfile(SCORE_PATH), f"Required program {SCORE_PATH} does not exist."
    assert not os.path.islink(SCORE_PATH), f"{SCORE_PATH} must be a regular source file."
    spec = importlib.util.spec_from_file_location("submitted_score", SCORE_PATH)
    assert spec is not None and spec.loader is not None, "Could not load score.py."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stable_reference(x):
    shifted = x - np.max(x)
    weights = np.exp(shifted)
    return weights / np.sum(weights)


def test_softmax_is_numerically_stable_on_derived_inputs():
    module = load_score_module()
    assert hasattr(module, "softmax") and callable(module.softmax), (
        "score.py must define a callable softmax function."
    )

    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(16), "big"))
    cases = [
        np.array([1000.0, 1001.0, 1002.0]),
        np.array([-1002.0, -1001.0, -1000.0]),
    ]
    for _ in range(8):
        size = int(rng.integers(3, 20))
        offset = float(rng.uniform(-1_000_000.0, 1_000_000.0))
        cases.append(offset + rng.normal(0.0, 20.0, size=size))

    for values in cases:
        expected = stable_reference(values)
        actual = np.asarray(module.softmax(values.copy()), dtype=float)
        assert actual.shape == values.shape, "softmax returned an array with the wrong shape."
        assert np.all(np.isfinite(actual)), "softmax produced NaN or infinity."
        assert np.isclose(np.sum(actual), 1.0, rtol=1e-12, atol=1e-12), (
            "softmax probabilities do not sum to 1."
        )
        assert np.allclose(actual, expected, rtol=1e-11, atol=1e-13), (
            "softmax is incorrect for large-magnitude input values."
        )


def test_score_program_runs_and_report_matches_its_output():
    run = subprocess.run(
        ["python3", SCORE_PATH],
        cwd=REPO_PATH,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert run.returncode == 0, f"score.py failed to run: {run.stderr}"
    output = run.stdout.strip()
    assert output.startswith("[") and output.endswith("]"), (
        f"score.py did not print the expected output array: {output!r}"
    )
    values = np.fromstring(output[1:-1], sep=" ")
    assert values.size == 3, f"Expected three softmax values, got: {output!r}"
    assert np.all(np.isfinite(values)), "Running score.py still produces NaN or infinity."

    expected = stable_reference(np.array([1000.0, 1001.0, 1002.0]))
    assert np.allclose(values, expected, rtol=1e-7, atol=1e-8), (
        f"score.py printed an incorrect array: {values}"
    )
    with open(REPORT_PATH, "r") as f:
        report_data = json.load(f)
    assert report_data["softmax_first_value"] == round(float(expected[0]), 4), (
        "The report does not contain the first executed softmax value rounded to 4 places."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
