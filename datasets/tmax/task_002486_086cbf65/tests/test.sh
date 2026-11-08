#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

SCRIPT_PATH = "/home/user/filter_artifacts.py"
RAW_PATH = "/app/data/raw_features.csv"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"


def expected_valid(path, canonical):
    try:
        artifact = pd.read_csv(path, header=None).to_numpy(dtype=float)
    except Exception:
        return False
    return (
        artifact.shape == canonical.shape
        and np.isfinite(artifact).all()
        and np.allclose(artifact, canonical, atol=1e-5, rtol=0)
    )


def run_case(path, should_accept):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "--input", path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    expected_stdout = "ACCEPT" if should_accept else "REJECT"
    expected_code = 0 if should_accept else 1
    assert result.returncode == expected_code, (
        f"For randomized input {os.path.basename(path)}, expected exit "
        f"{expected_code}, got {result.returncode}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected_stdout, (
        f"For randomized input {os.path.basename(path)}, expected "
        f"{expected_stdout}, got stdout={result.stdout!r}"
    )


def test_adversarial_corpus_and_generated_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing at {CLEAN_DIR}"
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing at {EVIL_DIR}"

    clean_files = sorted(f for f in os.listdir(CLEAN_DIR) if f.endswith(".csv"))
    evil_files = sorted(f for f in os.listdir(EVIL_DIR) if f.endswith(".csv"))
    assert clean_files, "No clean files found."
    assert evil_files, "No evil files found."

    raw = pd.read_csv(RAW_PATH).to_numpy(dtype=float)
    scaled = StandardScaler().fit_transform(raw)
    canonical = PCA(n_components=3, random_state=42).fit_transform(scaled)

    # A different random_state has no effect with PCA's deterministic solver for
    # this data, so these artifacts are valid according to the instruction.
    alternate_seed = PCA(n_components=3, random_state=99).fit_transform(scaled)
    assert np.allclose(alternate_seed, canonical, atol=1e-12, rtol=0)

    rng = np.random.default_rng()
    with tempfile.TemporaryDirectory(prefix="artifact-validation-") as temp_dir:
        cases = []

        # Preserve the original corpus coverage, but invoke the submission only
        # on randomized paths and derive each expected answer from its contents.
        for source_dir, names in ((CLEAN_DIR, clean_files), (EVIL_DIR, evil_files)):
            for name in names:
                source = os.path.join(source_dir, name)
                target = os.path.join(temp_dir, f"{uuid.uuid4().hex}.csv")
                shutil.copyfile(source, target)
                valid = expected_valid(target, canonical)
                if source_dir == CLEAN_DIR:
                    assert valid, f"Clean corpus artifact is not canonical: {name}"
                cases.append((target, valid))

        # Explicitly confirm the formerly mislabelled wrong-seed subset is valid.
        for index in range(5, 10):
            source = os.path.join(EVIL_DIR, f"artifact_{index}.csv")
            assert expected_valid(source, canonical), (
                f"artifact_{index}.csv should match deterministic PCA output"
            )

        generated = [
            (canonical, True),
            (canonical + rng.uniform(-5e-6, 5e-6, canonical.shape), True),
            (alternate_seed, True),
            (PCA(n_components=3, random_state=42).fit_transform(raw), False),
            (PCA(n_components=4, random_state=42).fit_transform(scaled), False),
        ]

        large_error = canonical.copy()
        large_error[rng.integers(0, large_error.shape[0]), rng.integers(0, 3)] += 1e-3
        generated.append((large_error, False))

        for matrix, valid in generated:
            target = os.path.join(temp_dir, f"{uuid.uuid4().hex}.csv")
            pd.DataFrame(matrix).to_csv(target, index=False, header=False)
            assert expected_valid(target, canonical) == valid
            cases.append((target, valid))

        malformed = os.path.join(temp_dir, f"{uuid.uuid4().hex}.csv")
        with open(malformed, "w", encoding="utf-8") as handle:
            handle.write("not,a,numeric,embedding\n1,2,broken,4\n")
        cases.append((malformed, False))

        rng.shuffle(cases)
        for path, valid in cases:
            run_case(path, valid)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
