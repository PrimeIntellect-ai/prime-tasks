#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import math
import os
import random
import subprocess
import sys

import pytest
import requests


def reference_score(seq):
    weights = {'A': 1.0, 'C': 2.0, 'G': 3.0, 'T': 4.0}
    return sum(weights.get(ch, 0.0) for ch in seq)


def test_package_installed():
    try:
        import seq_scorer
    except ImportError:
        pytest.fail("The 'seq_scorer' package is not installed or cannot be imported.")

    module_path = os.path.realpath(getattr(seq_scorer, '__file__', ''))
    assert os.path.isfile(module_path), "seq_scorer has no installed module file"
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
        f"seq_scorer must be a compiled extension, got {module_path}"
    assert isinstance(seq_scorer.__spec__.loader, importlib.machinery.ExtensionFileLoader), \
        "seq_scorer was not loaded as a compiled extension"

    setup_dir = '/app/vendored/seq_scorer-1.0.0'
    result = subprocess.run(
        [sys.executable, 'setup.py', 'build_ext', '--inplace'],
        cwd=setup_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Vendored extension still fails to compile:\n{result.stdout}"

    fixed_cases = {
        '': 0.0,
        'A': 1.0,
        'C': 2.0,
        'G': 3.0,
        'T': 4.0,
        'ATGC': 10.0,
        'AAAACCCGGTT': 23.0,
        'NAXtgC': 3.0,
    }
    for seq, expected in fixed_cases.items():
        assert math.isclose(seq_scorer.score_sequence(seq), expected, rel_tol=1e-12, abs_tol=1e-12), \
            f"Compiled seq_scorer returned an incorrect score for {seq!r}"

    rng = random.SystemRandom()
    for _ in range(25):
        seq = ''.join(rng.choice('ACGT') for _ in range(rng.randrange(1, 250)))
        expected = reference_score(seq)
        assert math.isclose(seq_scorer.score_sequence(seq), expected, rel_tol=1e-12, abs_tol=1e-12), \
            f"Compiled seq_scorer returned an incorrect score for {seq!r}"


def get_expected_stats():
    try:
        import h5py
        import numpy as np
    except ImportError:
        pytest.fail("Missing required libraries 'h5py' or 'numpy' to verify expected stats.")

    path = "/app/data/observational.h5"
    assert os.path.isfile(path), f"File {path} does not exist."

    with h5py.File(path, 'r') as f:
        assert 'reads' in f, "HDF5 file is missing the 'reads' dataset"
        reads = [x.decode('utf-8') if isinstance(x, bytes) else x for x in f['reads'][:]]

    # Derive the oracle independently from the documented vendored C algorithm.
    scores = [reference_score(seq) for seq in reads]
    mean_score = float(np.mean(scores))

    np.random.seed(42)
    boot_means = []
    n = len(scores)
    for _ in range(10000):
        resample = np.random.choice(scores, size=n, replace=True)
        boot_means.append(np.mean(resample))

    ci_lower = float(np.percentile(boot_means, 2.5))
    ci_upper = float(np.percentile(boot_means, 97.5))
    return mean_score, ci_lower, ci_upper


def test_api_ci_endpoint():
    mean_score, ci_lower, ci_upper = get_expected_stats()
    url = "http://127.0.0.1:8080/ci"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    data = response.json()
    assert "mean" in data, "Response missing 'mean' field"
    assert "ci_lower" in data, "Response missing 'ci_lower' field"
    assert "ci_upper" in data, "Response missing 'ci_upper' field"
    assert math.isclose(data["mean"], mean_score, rel_tol=1e-4), f"Expected mean {mean_score}, got {data['mean']}"
    assert math.isclose(data["ci_lower"], ci_lower, rel_tol=1e-4), f"Expected ci_lower {ci_lower}, got {data['ci_lower']}"
    assert math.isclose(data["ci_upper"], ci_upper, rel_tol=1e-4), f"Expected ci_upper {ci_upper}, got {data['ci_upper']}"


def test_api_score_endpoint():
    import seq_scorer
    mean_score, ci_lower, ci_upper = get_expected_stats()
    url = "http://127.0.0.1:8080/score"

    test_sequences = [
        "ATGC",
        "GGCC",
        "AATT",
        "ATGCATGCATGCATGC",
        "GCGCGCGCGCGCGCGC",
    ]
    rng = random.SystemRandom()
    test_sequences.extend(
        ''.join(rng.choice('ACGT') for _ in range(rng.randrange(80, 140)))
        for _ in range(20)
    )

    for seq in test_sequences:
        oracle_score = reference_score(seq)
        installed_score = seq_scorer.score_sequence(seq)
        assert math.isclose(installed_score, oracle_score, rel_tol=1e-12, abs_tol=1e-12), \
            f"Installed extension returned the wrong score for {seq!r}"
        expected_score = installed_score
        expected_anomalous = expected_score < ci_lower or expected_score > ci_upper

        try:
            response = requests.post(url, json={"sequence": seq}, timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to {url}: {e}")

        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
        data = response.json()
        assert "score" in data, "Response missing 'score' field"
        assert "is_anomalous" in data, "Response missing 'is_anomalous' field"
        assert math.isclose(data["score"], expected_score, rel_tol=1e-4), \
            f"For seq {seq}, expected score {expected_score}, got {data['score']}"
        assert data["is_anomalous"] == expected_anomalous, \
            f"For seq {seq}, expected is_anomalous {expected_anomalous}, got {data['is_anomalous']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
