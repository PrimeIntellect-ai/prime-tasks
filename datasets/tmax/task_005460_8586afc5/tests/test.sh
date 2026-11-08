#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile
import uuid

import numpy as np
import pytest
from scipy.stats import wasserstein_distance

DETECTOR = "/home/user/detector.py"
BINS = np.arange(256, dtype=float)


def run_detector(filepath):
    result = subprocess.run(
        ["python3", DETECTOR, filepath],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Detector exited with status {result.returncode} for {filepath}: "
        f"{result.stderr}"
    )
    return result.stdout.strip()


def trace_max_distance(filepath):
    rows = np.loadtxt(filepath, delimiter=",", dtype=float)
    rows = np.atleast_2d(rows)
    assert rows.shape[0] >= 2
    assert rows.shape[1] == 256
    assert np.all(rows >= 0)
    assert np.all(rows.sum(axis=1) > 0)
    return max(
        wasserstein_distance(BINS, BINS, u_weights=a, v_weights=b)
        for a, b in zip(rows[:-1], rows[1:])
    )


def test_detector_exists():
    assert os.path.isfile(DETECTOR), f"Detector script missing: {DETECTOR}"


def test_detector_clean_corpus():
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.csv')]
    assert len(clean_files) > 0, "No CSV files found in clean corpus"

    failed_files = []

    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        result = subprocess.run(
            ["python3", "/home/user/detector.py", filepath],
            capture_output=True, text=True
        )
        output = result.stdout.strip()
        if output != "ACCEPT":
            failed_files.append((filename, output))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected incorrectly.\n"
        error_msg += "Offending files:\n" + "\n".join(f"{f}: {out}" for f, out in failed_files)
        pytest.fail(error_msg)


def test_detector_evil_corpus():
    evil_dir = "/app/corpus/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No CSV files found in evil corpus"

    failed_files = []

    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run(
            ["python3", "/home/user/detector.py", filepath],
            capture_output=True, text=True
        )
        output = result.stdout.strip()
        if output != "REJECT":
            failed_files.append((filename, output))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(evil_files)} evil files bypassed/accepted incorrectly.\n"
        error_msg += "Offending files:\n" + "\n".join(f"{f}: {out}" for f, out in failed_files)
        pytest.fail(error_msg)


def test_detector_on_unlabeled_generated_traces():
    clean_paths = sorted(
        os.path.join("/app/corpus/clean", name)
        for name in os.listdir("/app/corpus/clean")
        if name.endswith(".csv")
    )
    evil_paths = sorted(
        os.path.join("/app/corpus/evil", name)
        for name in os.listdir("/app/corpus/evil")
        if name.endswith(".csv")
    )
    assert clean_paths and evil_paths

    clean_max = max(trace_max_distance(path) for path in clean_paths)
    evil_min = min(trace_max_distance(path) for path in evil_paths)
    assert clean_max < evil_min, "Corpus no longer has a Wasserstein-separable gap"
    assert clean_max >= 1.0 and evil_min < 50.0, "Corpus calibration is invalid"

    accept_limit = int(math.floor(clean_max))
    reject_start = int(math.ceil(evil_min))
    assert accept_limit >= 1 and reject_start <= 50

    rng = secrets.SystemRandom()
    cases = []
    with tempfile.TemporaryDirectory(prefix="tracecheck_") as case_dir:
        for expected in (["ACCEPT"] * 8 + ["REJECT"] * 8):
            if expected == "ACCEPT":
                shift = rng.randint(0, accept_limit)
            else:
                shift = rng.randint(reject_start, min(50, reject_start + 20))

            base = np.zeros(256, dtype=np.int64)
            for _ in range(rng.randint(25, 60)):
                base[rng.randint(55, 175)] += rng.randint(1, 40)

            moved = np.zeros(256, dtype=np.int64)
            if shift == 0:
                moved[:] = base
            else:
                moved[shift:] = base[:-shift]

            # Independent row scaling checks that rows are treated as histogram
            # weights rather than compared as raw vectors.
            rows = []
            for step in range(15):
                histogram = base if step < 7 else moved
                rows.append(histogram * rng.randint(1, 9))

            path = os.path.join(case_dir, uuid.uuid4().hex + ".csv")
            np.savetxt(path, np.asarray(rows), delimiter=",", fmt="%d")
            measured = trace_max_distance(path)
            if expected == "ACCEPT":
                assert measured <= clean_max + 1e-9
            else:
                assert measured >= evil_min - 1e-9
            cases.append((path, expected, measured))

        rng.shuffle(cases)
        failures = []
        for path, expected, measured in cases:
            output = run_detector(path)
            if output != expected:
                failures.append((os.path.basename(path), measured, expected, output))

        assert not failures, "Generated trace failures: " + repr(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
