#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import json
import math
import os
import random
import secrets
import subprocess
import sys
import uuid

import pytest


def make_nested_log(depth):
    token = secrets.token_hex(12)
    value = "$(printf '" + token + "')"
    for _ in range(depth):
        key = "field_" + uuid.uuid4().hex
        encoded_json = json.dumps({key: value}, separators=(",", ":")).encode("utf-8")
        value = base64.b64encode(encoded_json).decode("ascii")
    return json.dumps({"entry_" + uuid.uuid4().hex: value}, separators=(",", ":"))


def run_classifier(classifier_path, path):
    try:
        return subprocess.run(
            ["python3", classifier_path, path],
            capture_output=True,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Classifier timed out on {path}")


def test_anomaly_solver_fixed():
    path = "/home/user/anomaly_solver.py"
    assert os.path.isfile(path), f"Missing anomaly_solver.py file at {path}"

    with open(path, "r") as f:
        content = f.read()

    assert "0.997" in content, "anomaly_solver.py does not contain the corrected decay constant (0.997)"
    assert "N - 2" in content, "anomaly_solver.py does not contain the corrected denominator (N - 2)"
    assert "0.85" not in content, "anomaly_solver.py still contains the flawed decay constant (0.85)"
    assert "N - 1" not in content, "anomaly_solver.py still contains the flawed denominator (N - 1)"

    rng = random.SystemRandom()
    datasets = [
        [1.25, -3.5, 8.0],
        [0.0, 2.0, 4.0, 6.0],
        [rng.uniform(-50, 50) for _ in range(5)],
        [rng.uniform(-100, 100) for _ in range(9)],
    ]
    helper = r'''
import importlib.util
import json
import sys
spec = importlib.util.spec_from_file_location("submitted_anomaly_solver", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
if not callable(getattr(module, "compute_baseline", None)):
    raise TypeError("compute_baseline is missing or not callable")
data = json.loads(sys.argv[2])
results = [module.compute_baseline(case) for case in data]
print("VERIFIER_RESULT=" + json.dumps(results))
'''
    result = subprocess.run(
        [sys.executable, "-c", helper, path, json.dumps(datasets)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Executing compute_baseline failed: {result.stderr}"
    lines = [line for line in result.stdout.splitlines() if line.startswith("VERIFIER_RESULT=")]
    assert len(lines) == 1, "Could not obtain results from compute_baseline"
    actual = json.loads(lines[0].split("=", 1)[1])
    assert len(actual) == len(datasets)
    for data, observed in zip(datasets, actual):
        expected = 0.997 * (sum(data) / (len(data) - 2))
        assert isinstance(observed, (int, float)) and math.isfinite(observed)
        assert observed == pytest.approx(expected, rel=1e-10, abs=1e-10), (
            f"compute_baseline({data!r}) returned {observed!r}, expected {expected!r}"
        )


def test_incident_report_log():
    path = "/home/user/incident_report.log"
    assert os.path.isfile(path), f"Missing incident_report.log file at {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "0.997", f"incident_report.log does not contain exactly '0.997', found: '{content}'"


def test_classifier_corpus():
    classifier_path = "/home/user/classifier.py"
    assert os.path.isfile(classifier_path), f"Missing classifier script at {classifier_path}"

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    # Replace the setup's empty placeholders with representative corpus entries.
    with open(os.path.join(clean_dir, "log1.txt"), "w") as f:
        f.write(make_nested_log(3))
    with open(os.path.join(evil_dir, "log1.txt"), "w") as f:
        f.write(make_nested_log(4))

    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, "No files found in clean corpus"
    assert len(evil_files) > 0, "No files found in evil corpus"

    clean_failures = []
    for cf in clean_files:
        if not os.path.isfile(cf):
            continue
        result = subprocess.run(["python3", classifier_path, cf], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        if not os.path.isfile(ef):
            continue
        result = subprocess.run(["python3", classifier_path, ef], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(ef))

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/flagged: {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")

    assert not error_messages, "Classifier failed on corpus:\n" + "\n".join(error_messages)


def test_classifier_decodes_nested_values_without_path_hints(tmp_path):
    classifier_path = "/home/user/classifier.py"
    assert os.path.isfile(classifier_path), f"Missing classifier script at {classifier_path}"

    neutral_dir = tmp_path / ("samples_" + uuid.uuid4().hex)
    neutral_dir.mkdir()

    cases = []
    for depth, expected_code in [(0, 0), (1, 0), (2, 0), (3, 0), (4, 1), (5, 1), (7, 1)]:
        path = neutral_dir / (uuid.uuid4().hex + ".dat")
        path.write_text(make_nested_log(depth), encoding="utf-8")
        cases.append((path, expected_code, depth))

    plain_path = neutral_dir / (uuid.uuid4().hex + ".dat")
    plain_path.write_text(json.dumps({"message": "ordinary safe log data"}), encoding="utf-8")
    cases.append((plain_path, 0, 0))

    random.SystemRandom().shuffle(cases)
    for path, expected_code, depth in cases:
        observed = run_classifier(classifier_path, str(path))
        assert observed == expected_code, (
            f"Classifier returned {observed} for a neutral-path sample with {depth} "
            f"Base64/JSON layers; expected {expected_code}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
