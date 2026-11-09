#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import secrets
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest
from scipy.integrate import trapezoid
from scipy.signal import savgol_filter
from scipy.stats import wasserstein_distance

SCRIPT_PATH = "/home/user/profile_classifier.py"
THRESHOLD = 4.25


def run_classifier(file_path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, file_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def test_classifier_clean_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    clean_dir = "/app/corpora/clean"
    clean_files = sorted(glob.glob(os.path.join(clean_dir, "*.csv")))
    assert len(clean_files) > 0, "No clean corpus files found in /app/corpora/clean"

    failed_files = []
    for file_path in clean_files:
        result = run_classifier(file_path)
        if result.returncode != 0:
            failed_files.append(os.path.basename(file_path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean modified "
            f"(rejected instead of accepted). Offending files: {', '.join(failed_files)}"
        )


def test_classifier_evil_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    evil_dir = "/app/corpora/evil"
    evil_files = sorted(glob.glob(os.path.join(evil_dir, "*.csv")))
    assert len(evil_files) > 0, "No evil corpus files found in /app/corpora/evil"

    failed_files = []
    for file_path in evil_files:
        result = run_classifier(file_path)
        if result.returncode != 1:
            failed_files.append(os.path.basename(file_path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil bypassed "
            f"(accepted instead of rejected). Offending files: {', '.join(failed_files)}"
        )


def reference_distance(latency_ms, counts):
    smoothed = savgol_filter(counts, window_length=11, polyorder=3)
    smoothed = np.clip(smoothed, 0, None)
    area = trapezoid(smoothed, x=latency_ms)
    assert np.isfinite(area) and area > 0
    empirical_pdf = smoothed / area
    ideal_pdf = np.exp(-0.5 * ((latency_ms - 120.0) / 20.0) ** 2)
    ideal_pdf /= 20.0 * math.sqrt(2.0 * math.pi)
    return wasserstein_distance(
        latency_ms,
        latency_ms,
        u_weights=empirical_pdf,
        v_weights=ideal_pdf,
    )


def make_random_profile(rng):
    latency_ms = np.arange(241, dtype=float)
    mu1 = rng.uniform(105.0, 155.0)
    sigma1 = rng.uniform(11.0, 36.0)
    counts = np.exp(-0.5 * ((latency_ms - mu1) / sigma1) ** 2)

    if rng.random() < 0.65:
        mix = rng.uniform(0.05, 0.40)
        mu2 = rng.uniform(65.0, 210.0)
        sigma2 = rng.uniform(7.0, 32.0)
        second = np.exp(-0.5 * ((latency_ms - mu2) / sigma2) ** 2)
        counts = (1.0 - mix) * counts + mix * second

    counts *= rng.uniform(300.0, 3000.0)
    counts += rng.normal(0.0, rng.uniform(0.002, 0.025) * np.max(counts), counts.size)
    counts = np.clip(counts, 0, None)
    return latency_ms, counts


def test_classifier_on_opaque_generated_profiles():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    candidates = []
    for _ in range(600):
        latency_ms, counts = make_random_profile(rng)
        distance = reference_distance(latency_ms, counts)
        if np.isfinite(distance):
            candidates.append((distance, latency_ms, counts))

    # Exercise both sides near the specified boundary while avoiding numerical ties.
    accepted = sorted(
        (item for item in candidates if item[0] <= THRESHOLD - 0.35),
        key=lambda item: item[0],
        reverse=True,
    )[:6]
    rejected = sorted(
        (item for item in candidates if item[0] >= THRESHOLD + 0.35),
        key=lambda item: item[0],
    )[:6]
    assert len(accepted) == 6 and len(rejected) == 6, "Could not generate balanced profiles"

    cases = [(item, 0) for item in accepted] + [(item, 1) for item in rejected]
    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="profile_checks_") as temp_dir:
        for (distance, latency_ms, counts), expected_status in cases:
            # Every case shares one neutral directory and receives an opaque name;
            # neither the path nor filename discloses its expected classification.
            file_path = os.path.join(temp_dir, secrets.token_hex(12) + ".csv")
            pd.DataFrame({"latency_ms": latency_ms, "counts": counts}).to_csv(
                file_path, index=False
            )
            result = run_classifier(file_path)
            if result.returncode != expected_status:
                failures.append(
                    f"{os.path.basename(file_path)}: distance={distance:.8f}, "
                    f"expected={expected_status}, got={result.returncode}, "
                    f"stderr={result.stderr.decode(errors='replace')[-300:]}"
                )

    if failures:
        pytest.fail("Generated-profile classification failures:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
