#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import glob
import json
import math
import os
import secrets
import subprocess
import tempfile
import uuid

import cv2
import numpy as np
import pytest

EXECUTABLE = "/home/user/artifact_filter"
SOURCE = "/home/user/artifact_filter.cpp"


def derive_video_counts(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open video {path}."
    successes = 0
    failures = 0
    frames = 0
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            frames += 1
            mean = float(np.mean(frame))
            # Lossy MP4 decoding may move channel values slightly away from 0/255.
            if mean >= 240.0:
                successes += 1
            elif mean <= 15.0:
                failures += 1
            else:
                pytest.fail(f"Video frame {frames} is neither a white nor black frame (mean={mean}).")
    finally:
        cap.release()
    assert frames > 0, "Experiment video contains no decodable frames."
    return successes, failures


def test_video_results():
    results_path = "/home/user/video_results.json"
    assert os.path.exists(results_path), f"Expected results file at {results_path} does not exist."

    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    assert "successes" in data, "Missing 'successes' key in JSON."
    assert "failures" in data, "Missing 'failures' key in JSON."

    expected_successes, expected_failures = derive_video_counts("/app/experiment.mp4")
    assert data["successes"] == expected_successes, f"Expected {expected_successes} successes, got {data['successes']}."
    assert data["failures"] == expected_failures, f"Expected {expected_failures} failures, got {data['failures']}."


def test_artifact_filter_executable():
    assert os.path.exists(EXECUTABLE), f"Compiled binary {EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"Expected {EXECUTABLE} to be a file."
    assert os.access(EXECUTABLE, os.X_OK), f"Binary {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled Linux executable."

    assert os.path.exists(SOURCE), f"Expected C++ source file at {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"Expected {SOURCE} to be a file."


def run_filter(executable, path):
    try:
        return subprocess.run([executable, path], capture_output=True, timeout=5).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out while processing {path}.")


def test_adversarial_corpus_filtering():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.exists(EXECUTABLE), f"Missing executable {EXECUTABLE}"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}."
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}."

    failed_clean = []
    for path in clean_files:
        if run_filter(EXECUTABLE, path) != 0:
            failed_clean.append(os.path.basename(path))

    failed_evil = []
    for path in evil_files:
        if run_filter(EXECUTABLE, path) == 0:
            failed_evil.append(os.path.basename(path))

    error_msgs = []
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified: {', '.join(failed_clean)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def make_valid(successes, failures, prior_alpha, prior_beta):
    alpha_post = prior_alpha + successes
    beta_post = prior_beta + failures
    total = alpha_post + beta_post
    return {
        "experiment_id": "hidden_" + uuid.uuid4().hex,
        "successes": successes,
        "failures": failures,
        "prior_alpha": prior_alpha,
        "prior_beta": prior_beta,
        "posterior_mean": alpha_post / total,
        "posterior_variance": (alpha_post * beta_post) / ((total ** 2) * (total + 1.0)),
    }


def write_json(path, value):
    with open(path, "w") as f:
        json.dump(value, f, allow_nan=True)


def test_generated_hidden_cases_and_source_build():
    assert os.path.isfile(SOURCE), f"Missing source file {SOURCE}."
    assert os.path.isfile(EXECUTABLE), f"Missing executable {EXECUTABLE}."

    with tempfile.TemporaryDirectory(prefix="artifact_checks_") as temp_dir:
        rebuilt = os.path.join(temp_dir, "rebuilt_filter")
        build = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"artifact_filter.cpp does not compile:\n{build.stderr}"

        valid_cases = []
        for _ in range(12):
            successes = secrets.randbelow(5000)
            failures = secrets.randbelow(5000)
            prior_alpha = (secrets.randbelow(10000) + 1) / 137.0
            prior_beta = (secrets.randbelow(10000) + 1) / 193.0
            valid_cases.append(make_valid(successes, failures, prior_alpha, prior_beta))

        valid_cases.extend([
            make_valid(0, 0, 1.0, 1.0),
            make_valid(0, 37, 0.25, 3.75),
            make_valid(91, 0, 12.5, 0.125),
        ])

        tolerance_case_mean = make_valid(17, 29, 2.25, 4.5)
        tolerance_case_mean["posterior_mean"] += 0.00009
        valid_cases.append(tolerance_case_mean)
        tolerance_case_variance = make_valid(53, 71, 1.75, 2.5)
        tolerance_case_variance["posterior_variance"] += 0.00009
        valid_cases.append(tolerance_case_variance)

        base = make_valid(23, 41, 1.5, 2.75)
        invalid_cases = []
        for key, value in [
            ("successes", -1),
            ("failures", -7),
            ("successes", 3.0),
            ("failures", 4.5),
            ("successes", True),
            ("prior_alpha", 0.0),
            ("prior_beta", 0.0),
            ("prior_alpha", -0.25),
            ("prior_beta", -2.0),
            ("successes", "23"),
            ("posterior_mean", None),
        ]:
            item = copy.deepcopy(base)
            item[key] = value
            invalid_cases.append(item)

        bad_mean = copy.deepcopy(base)
        bad_mean["posterior_mean"] += 0.00011
        invalid_cases.append(bad_mean)
        bad_variance = copy.deepcopy(base)
        bad_variance["posterior_variance"] += 0.00011
        invalid_cases.append(bad_variance)
        nan_mean = copy.deepcopy(base)
        nan_mean["posterior_mean"] = float("nan")
        invalid_cases.append(nan_mean)
        inf_variance = copy.deepcopy(base)
        inf_variance["posterior_variance"] = float("inf")
        invalid_cases.append(inf_variance)
        missing = copy.deepcopy(base)
        del missing["posterior_variance"]
        invalid_cases.append(missing)
        invalid_cases.append([base])

        valid_paths = []
        invalid_paths = []
        for item in valid_cases:
            path = os.path.join(temp_dir, uuid.uuid4().hex + ".json")
            write_json(path, item)
            valid_paths.append(path)
        for item in invalid_cases:
            path = os.path.join(temp_dir, uuid.uuid4().hex + ".json")
            write_json(path, item)
            invalid_paths.append(path)

        malformed_path = os.path.join(temp_dir, uuid.uuid4().hex + ".json")
        with open(malformed_path, "w") as f:
            f.write('{"successes": 3, "failures":')
        invalid_paths.append(malformed_path)

        for executable in (EXECUTABLE, rebuilt):
            for path in valid_paths:
                rc = run_filter(executable, path)
                assert rc == 0, f"{executable} rejected generated valid artifact {os.path.basename(path)} with exit code {rc}."
            for path in invalid_paths:
                rc = run_filter(executable, path)
                assert rc == 1, f"{executable} did not exit 1 for invalid artifact {os.path.basename(path)} (exit code {rc})."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
