#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import numpy as np
import pandas as pd
import pytest


def build_hidden_corpus():
    root = tempfile.mkdtemp(prefix="corpus_")
    rng = np.random.default_rng(secrets.randbits(128))
    labels = [0] * 10 + [1] * 10
    secrets.SystemRandom().shuffle(labels)
    cases = []

    def generate_clean(n_samples=100, n_features=5):
        a = rng.standard_normal((n_features, n_features))
        cov = a @ a.T
        data = rng.multivariate_normal(np.zeros(n_features), cov, n_samples)
        return pd.DataFrame(data)

    def generate_evil(n_samples=100, n_features=5):
        data = generate_clean(n_samples, n_features - 1)
        weights = rng.standard_normal(n_features - 1)
        collinear = data.values @ weights + rng.standard_normal(n_samples) * 1e-4
        data[n_features - 1] = collinear
        return data

    for label in labels:
        path = os.path.join(root, secrets.token_hex(12) + ".csv")
        frame = generate_clean() if label == 0 else generate_evil()
        frame.to_csv(path, index=False)
        cases.append((path, label))
    return root, cases


CORPUS_ROOT, CORPUS_CASES = build_hidden_corpus()


def test_detector_corpus():
    detector_script = "/home/user/detector.py"
    assert os.path.isfile(detector_script), f"Detector script missing at {detector_script}"

    cases = list(CORPUS_CASES)
    secrets.SystemRandom().shuffle(cases)
    clean_failures = []
    evil_failures = []

    for path, expected in cases:
        result = subprocess.run(
            ["python3", detector_script, path],
            capture_output=True,
            timeout=15,
        )
        if expected == 0 and result.returncode != 0:
            clean_failures.append(os.path.basename(path))
        elif expected == 1 and result.returncode != 1:
            evil_failures.append(os.path.basename(path))

    error_messages = []
    if clean_failures:
        error_messages.append(
            f"{len(clean_failures)} of 10 clean datasets rejected: {', '.join(clean_failures)}"
        )
    if evil_failures:
        error_messages.append(
            f"{len(evil_failures)} of 10 evil datasets accepted: {', '.join(evil_failures)}"
        )
    assert not error_messages, " | ".join(error_messages)


def test_pipeline_e2e():
    try:
        urllib.request.urlopen("http://localhost:5000/", timeout=2)
    except urllib.error.HTTPError:
        pass
    except Exception as exc:
        pytest.fail(f"Flask API does not seem to be running on port 5000: {exc}")

    source_by_label = {
        label: next(path for path, case_label in CORPUS_CASES if case_label == label)
        for label in (0, 1)
    }
    submissions = []
    for label in (0, 1):
        path = os.path.join("/tmp", secrets.token_hex(16) + ".csv")
        shutil.copy(source_by_label[label], path)
        submissions.append((path, label))
    secrets.SystemRandom().shuffle(submissions)

    def post_file(file_path):
        request = urllib.request.Request(
            "http://localhost:5000/process",
            data=json.dumps({"file_path": file_path}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status
        except urllib.error.HTTPError as exc:
            return exc.code
        except Exception as exc:
            pytest.fail(f"Failed to POST to API: {exc}")

    expected_paths = []
    for path, label in submissions:
        destination = "/home/user/accepted" if label == 0 else "/home/user/rejected"
        expected = os.path.join(destination, os.path.basename(path))
        if os.path.exists(expected):
            os.remove(expected)
        expected_paths.append(expected)
        status = post_file(path)
        assert status in (200, 202), f"Expected 200/202 from API, got {status}"

    deadline = time.time() + 10
    while time.time() < deadline and not all(os.path.exists(path) for path in expected_paths):
        time.sleep(0.5)

    for expected in expected_paths:
        assert os.path.exists(expected), f"File was not routed to {expected} by the worker."

    for expected in expected_paths:
        if os.path.exists(expected):
            os.remove(expected)
    for path, _ in submissions:
        if os.path.exists(path):
            os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
