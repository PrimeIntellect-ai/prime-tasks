#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import subprocess
import sys
import tempfile
import uuid

import numpy as np
import pandas as pd
import pytest

DETECTOR = "/home/user/detector.py"
FEATURES = [f"feature_{i}" for i in range(10)]


def run_detector(path, env=None):
    return subprocess.run([sys.executable, DETECTOR, path], env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=30)


def test_fast_covar_installed():
    """Verify that the fast_covar package was successfully fixed and installed."""
    try:
        import fast_covar
    except ImportError:
        pytest.fail("fast_covar is not installed or importable. The agent failed to fix and install the vendored package.")


def test_detector_exists():
    """Verify that the detector script exists at the correct path."""
    assert os.path.exists(DETECTOR), "/home/user/detector.py does not exist."


def test_detector_clean_corpus():
    """Verify that the detector accepts all clean datasets (exit code 0)."""
    clean_dir = "/home/user/data/clean"
    assert os.path.exists(clean_dir), f"Clean data directory missing: {clean_dir}"

    modified_clean = []
    total_clean = 0
    for d in sorted(os.listdir(clean_dir)):
        ds_path = os.path.join(clean_dir, d)
        if os.path.isdir(ds_path):
            total_clean += 1
            result = run_detector(ds_path)
            if result.returncode != 0:
                modified_clean.append(d)

    assert len(modified_clean) == 0, f"{len(modified_clean)} of {total_clean} clean modified/rejected: {modified_clean}"


def test_detector_evil_corpus():
    """Verify that the detector rejects all evil datasets (exit code 1)."""
    evil_dir = "/home/user/data/evil"
    assert os.path.exists(evil_dir), f"Evil data directory missing: {evil_dir}"

    bypassed_evil = []
    total_evil = 0
    for d in sorted(os.listdir(evil_dir)):
        ds_path = os.path.join(evil_dir, d)
        if os.path.isdir(ds_path):
            total_evil += 1
            result = run_detector(ds_path)
            if result.returncode != 1:
                bypassed_evil.append(d)

    assert len(bypassed_evil) == 0, f"{len(bypassed_evil)} of {total_evil} evil bypassed: {bypassed_evil}"


def whiten(train, test, joint):
    fit = np.vstack([train, test]) if joint else train
    mean = fit.mean(axis=0)
    cov = np.cov(fit - mean, rowvar=False)
    inv_sqrt = np.linalg.inv(np.linalg.cholesky(cov))
    return (train - mean) @ inv_sqrt.T, (test - mean) @ inv_sqrt.T


def write_case(path, rng, evil):
    n_train = int(rng.integers(73, 167))
    n_test = int(rng.integers(31, 94))
    train = rng.normal(size=(n_train, 10)) * rng.uniform(0.8, 4.0, 10) + rng.normal(size=10)
    test = rng.normal(size=(n_test, 10)) * rng.uniform(0.8, 4.0, 10) + rng.normal(size=10)
    train, test = whiten(train, test, joint=evil)

    os.makedirs(path)
    frames = []
    for values in (train, test):
        df = pd.DataFrame(values, columns=FEATURES)
        df["id"] = rng.normal(1e9, 1e7, len(df))
        df["target"] = rng.normal(-1e8, 1e6, len(df))
        df["unrelated_numeric_column"] = rng.normal(5e10, 1e9, len(df))

        # These rows must disappear under the required feature-schema null filtering.
        bad = pd.DataFrame(rng.normal(9e7, 1e5, (3, 10)), columns=FEATURES)
        for i in range(3):
            bad.loc[i, FEATURES[i]] = np.nan
        bad["id"] = rng.normal(size=3)
        bad["target"] = rng.normal(size=3)
        bad["unrelated_numeric_column"] = rng.normal(size=3)
        frames.append(pd.concat([df, bad], ignore_index=True))

    frames[0].to_csv(os.path.join(path, "train.csv"), index=False)
    frames[1].to_csv(os.path.join(path, "test.csv"), index=False)


def expected_covariances(path):
    train = pd.read_csv(os.path.join(path, "train.csv"))[FEATURES].dropna().to_numpy(dtype=float)
    test = pd.read_csv(os.path.join(path, "test.csv"))[FEATURES].dropna().to_numpy(dtype=float)
    return train, np.vstack([train, test])


def used_fast_covar_for(marker, expected_matrices):
    if not os.path.exists(marker):
        return False
    records = []
    with open(marker) as f:
        for line in f:
            records.append(json.loads(line))

    for expected in expected_matrices:
        expected_cov = np.cov(expected, rowvar=False)
        matched = False
        for record in records:
            if record.get("shape") != list(expected.shape):
                continue
            actual_cov = np.asarray(record.get("cov"), dtype=float)
            if actual_cov.shape == (10, 10) and np.allclose(actual_cov, expected_cov, rtol=1e-9, atol=1e-10):
                matched = True
                break
        if not matched:
            return False
    return True


def test_detector_on_unlabeled_generated_cases_and_fast_covar_usage():
    """Exercise fresh neutral paths, varied sizes, schema decoys, nulls, and both whitening modes."""
    seed = int.from_bytes(os.urandom(16), "big")
    rng = np.random.default_rng(seed)

    with tempfile.TemporaryDirectory(prefix="detector_hidden_") as root:
        shim_dir = os.path.join(root, "instrumentation")
        os.makedirs(shim_dir)
        with open(os.path.join(shim_dir, "fast_covar.py"), "w") as f:
            f.write('''import json\nimport os\nimport numpy as np\n\ndef compute_cov(matrix):\n    array = np.asarray(matrix, dtype=float)\n    result = np.cov(array, rowvar=False)\n    marker = os.environ.get("FAST_COVAR_MARKER")\n    if marker:\n        with open(marker, "a") as out:\n            out.write(json.dumps({"shape": list(array.shape), "cov": result.tolist()}) + "\\n")\n    return result\n''')

        cases = []
        # Labels are deliberately mixed and are never included in directory names.
        labels = [False, True, True, False, True, False, False, True]
        random.SystemRandom().shuffle(labels)
        for evil in labels:
            path = os.path.join(root, "case_" + uuid.uuid4().hex)
            write_case(path, rng, evil)
            cases.append((path, evil))
        random.SystemRandom().shuffle(cases)

        failures = []
        for index, (path, evil) in enumerate(cases):
            marker = os.path.join(root, f"calls_{index}_{uuid.uuid4().hex}.jsonl")
            env = os.environ.copy()
            env["FAST_COVAR_MARKER"] = marker
            env["PYTHONPATH"] = shim_dir + os.pathsep + env.get("PYTHONPATH", "")
            result = run_detector(path, env=env)
            expected_code = 1 if evil else 0
            if result.returncode != expected_code:
                failures.append((os.path.basename(path), expected_code, result.returncode, result.stderr[-500:]))
                continue

            matrices = expected_covariances(path)
            assert used_fast_covar_for(marker, matrices), (
                "detector did not call fast_covar.compute_cov on both the filtered "
                "train matrix and filtered concatenated train/test matrix"
            )

        assert not failures, f"Generated neutral-path classification failures (seed={seed}): {failures}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
