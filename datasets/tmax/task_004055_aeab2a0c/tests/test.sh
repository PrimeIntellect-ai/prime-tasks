#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/sanitizer.py"


def run_sanitizer(path, *extra):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path, *extra],
        capture_output=True,
        timeout=15,
    )


def test_features_csv_exists():
    """Verify that the features.csv file was generated."""
    features_path = "/home/user/features.csv"
    assert os.path.isfile(features_path), f"Features CSV is missing at {features_path}"
    assert os.path.getsize(features_path) > 0, f"Features CSV at {features_path} is empty"


def test_required_packages_and_features_are_real_mfccs():
    """Recompute 13 MFCCs from the supplied recording and compare with the CSV."""
    checker = "/tmp/check_features.py"
    with open(checker, "w") as f:
        f.write(r'''
import sys
import numpy as np
try:
    import pandas as pd
    import librosa
except Exception as exc:
    print("pandas/librosa import failed:", exc)
    sys.exit(2)

expected = []
for kwargs in ({}, {"sr": None}):
    y, sr = librosa.load("/app/recording.wav", **kwargs)
    expected.append(librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13))

candidates = []
for header in (0, None):
    try:
        frame = pd.read_csv("/home/user/features.csv", header=header)
        numeric = frame.apply(pd.to_numeric, errors="coerce").to_numpy(dtype=float)
        if numeric.size and np.isfinite(numeric).all():
            candidates.append(numeric)
            if numeric.shape[1] > 1:
                first = numeric[:, 0]
                if np.array_equal(first, np.arange(len(first))):
                    candidates.append(numeric[:, 1:])
    except Exception:
        pass

for actual in candidates:
    for wanted in expected:
        if actual.shape == wanted.shape and np.allclose(actual, wanted, rtol=1e-4, atol=1e-4):
            sys.exit(0)
        if actual.shape == wanted.T.shape and np.allclose(actual, wanted.T, rtol=1e-4, atol=1e-4):
            sys.exit(0)

print("features.csv is not the 13-MFCC matrix derived from /app/recording.wav")
print("candidate shapes:", [x.shape for x in candidates])
print("expected shapes:", [x.shape for x in expected])
sys.exit(1)
''')

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", checker],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_single_thread_numerical_backend():
    """Check the numerical backend from a fresh user terminal session."""
    checker = "/tmp/check_backend.py"
    with open(checker, "w") as f:
        f.write(r'''
import json
import sys
import numpy as np
try:
    from threadpoolctl import threadpool_info
except Exception as exc:
    print("threadpoolctl unavailable:", exc)
    sys.exit(2)

x = np.ones((64, 64))
_ = x @ x
blas = [entry for entry in threadpool_info() if entry.get("user_api") == "blas"]
print(json.dumps(blas, default=str))
if not blas or any(entry.get("num_threads") != 1 for entry in blas):
    sys.exit(1)
''')

    env = os.environ.copy()
    for name in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS", "BLIS_NUM_THREADS"):
        env.pop(name, None)
    command = (
        "env HOME=/home/user USER=user LOGNAME=user "
        "bash -lic 'python3 /tmp/check_backend.py'"
    )
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-c", command],
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, "Numerical BLAS backend is not configured for exactly one thread:\n" + result.stdout + result.stderr


def test_sanitizer_script_exists():
    """Verify that the sanitizer script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer script is missing at {SCRIPT_PATH}"


def test_sanitizer_clean_corpus():
    """Verify that the sanitizer accepts all clean CSVs."""
    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    assert len(clean_files) > 0, f"No CSV files found in clean corpus directory {clean_dir}"

    failed_files = []
    for csv_file in clean_files:
        result = run_sanitizer(csv_file)
        if result.returncode != 0:
            failed_files.append(os.path.basename(csv_file))
    assert len(failed_files) == 0, f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {failed_files}"


def test_sanitizer_evil_corpus():
    """Verify that the sanitizer rejects all evil CSVs."""
    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    assert len(evil_files) > 0, f"No CSV files found in evil corpus directory {evil_dir}"

    failed_files = []
    for csv_file in evil_files:
        result = run_sanitizer(csv_file)
        if result.returncode != 1:
            failed_files.append(os.path.basename(csv_file))
    assert len(failed_files) == 0, f"{len(failed_files)} of {len(evil_files)} evil bypassed: {failed_files}"


def test_sanitizer_on_randomized_hidden_cases():
    """Exercise fresh contents and paths so corpus-specific hardcoding cannot pass."""
    with tempfile.TemporaryDirectory(prefix="csv_validation_") as directory:
        for case_number in range(8):
            path = os.path.join(directory, secrets.token_hex(12) + ".csv")
            rows = []
            for row_number in range(2 + secrets.randbelow(5)):
                speaker = secrets.randbelow(2_000_001) - 1_000_000
                frame = secrets.randbelow(2_000_001) - 1_000_000
                rows.append([str(speaker), str(frame), f"{case_number}.{row_number}"])
            with open(path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["speaker_id", "frame_index", "feature_value"])
                writer.writerows(rows)
            result = run_sanitizer(path)
            assert result.returncode == 0, f"Random clean CSV rejected ({result.returncode}): {result.stderr!r}"

        corruptions = [
            (0, ""), (1, ""),
            (0, "NaN"), (1, "nan"),
            (0, "5.0"), (1, "-12.0"),
            (0, "1e3"), (1, "2E4"),
            (0, "Infinity"), (1, "-inf"),
        ]
        for column, bad_value in corruptions:
            path = os.path.join(directory, secrets.token_hex(12) + ".csv")
            speaker = str(secrets.randbelow(900000) + 1)
            frame = str(-(secrets.randbelow(900000) + 1))
            row = [speaker, frame, str(secrets.randbelow(1000) / 10)]
            row[column] = bad_value
            with open(path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["speaker_id", "frame_index", "feature_value"])
                writer.writerow(["7", "11", "0.25"])
                writer.writerow(row)
            result = run_sanitizer(path)
            assert result.returncode == 1, f"Random evil CSV bypassed ({result.returncode}) for value {bad_value!r}"


def test_sanitizer_requires_exactly_one_argument():
    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, timeout=15)
    assert result.returncode != 0, "Sanitizer accepted an invocation with no CSV argument"

    with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as f:
        f.write("speaker_id,frame_index\n1,2\n")
        path = f.name
    try:
        result = subprocess.run(["python3", SCRIPT_PATH, path, path], capture_output=True, timeout=15)
        assert result.returncode != 0, "Sanitizer accepted more than one command-line argument"
    finally:
        os.unlink(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
