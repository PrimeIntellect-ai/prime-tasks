#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import subprocess
import tempfile
import uuid

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

SCRIPT_PATH = "/home/user/gatekeeper.py"
MAX_CORR = 0.85
MIN_MSE = 0.12


def run_gatekeeper(csv_path):
    if not os.path.isfile(SCRIPT_PATH):
        return None
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, csv_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as exc:
        return str(exc)


def expected_status(df):
    features = df.drop(columns=["target"])
    corr = features.corr(method="pearson").abs().to_numpy()
    upper = corr[np.triu_indices_from(corr, k=1)]
    if np.any(upper > MAX_CORR):
        return "STATUS: REJECT"

    split = int(len(df) * 0.8)
    model = Ridge(alpha=0.5)
    model.fit(features.iloc[:split], df["target"].iloc[:split])
    predictions = model.predict(features.iloc[split:])
    mse = mean_squared_error(df["target"].iloc[split:], predictions)
    return "STATUS: REJECT" if mse < MIN_MSE else "STATUS: ACCEPT"


def assert_exact_status(csv_path, expected):
    output = run_gatekeeper(csv_path)
    assert output is not None, "gatekeeper.py script is missing."
    assert output == expected + "\n", (
        f"For {os.path.basename(csv_path)}, expected exact stdout "
        f"{expected!r} followed by a newline, but received {output!r}"
    )


def test_gatekeeper_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_clean_corpus_accepted():
    clean_dir = "/app/corpora/clean"
    csv_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    assert len(csv_files) > 0, f"No CSV files found in {clean_dir}"

    failures = []
    for csv_file in csv_files:
        output = run_gatekeeper(csv_file)
        if output != "STATUS: ACCEPT\n":
            failures.append(os.path.basename(csv_file))

    if failures:
        pytest.fail(
            f"{len(failures)} of {len(csv_files)} clean files rejected, failed, "
            f"or produced non-exact output: {', '.join(failures)}"
        )


def test_evil_corpus_rejected():
    evil_dir = "/app/corpora/evil"
    csv_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    assert len(csv_files) > 0, f"No CSV files found in {evil_dir}"

    failures = []
    for csv_file in csv_files:
        output = run_gatekeeper(csv_file)
        if output != "STATUS: REJECT\n":
            failures.append(os.path.basename(csv_file))

    if failures:
        pytest.fail(
            f"{len(failures)} of {len(csv_files)} evil files bypassed, failed, "
            f"or produced non-exact output: {', '.join(failures)}"
        )


def test_fresh_mixed_datasets_in_unlabelled_paths():
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    cases = []

    # Produce fresh clean cases, retaining only decisively accepting instances.
    while len(cases) < 3:
        n = int(rng.integers(90, 141))
        x = rng.normal(size=(n, 3))
        y = 0.7 * x[:, 0] - 0.25 * x[:, 2] + rng.normal(0, 1.0, n)
        df = pd.DataFrame(x, columns=["f1", "f2", "f3"])
        df["target"] = y
        if expected_status(df) == "STATUS: ACCEPT":
            cases.append(df)

    # Produce fresh low-MSE leakage cases with otherwise benign features.
    leakage_count = 0
    while leakage_count < 3:
        n = int(rng.integers(90, 141))
        x = rng.normal(size=(n, 3))
        y = 1.3 * x[:, 0] - 0.4 * x[:, 1] + rng.normal(0, 0.005, n)
        df = pd.DataFrame(x, columns=["f1", "f2", "f3"])
        df["target"] = y
        if expected_status(df) == "STATUS: REJECT" and df.drop(columns=["target"]).corr().abs().to_numpy()[np.triu_indices(3, 1)].max() <= MAX_CORR:
            cases.append(df)
            leakage_count += 1

    # Produce fresh correlation-poisoned cases.
    for _ in range(3):
        n = int(rng.integers(90, 141))
        base = rng.normal(size=n)
        x = np.column_stack((base, base * 0.95 + rng.normal(0, 0.01, n), rng.normal(size=n)))
        y = rng.normal(size=n)
        df = pd.DataFrame(x, columns=["f1", "f2", "f3"])
        df["target"] = y
        assert expected_status(df) == "STATUS: REJECT"
        cases.append(df)

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="artifact_batch_") as directory:
        for df in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".csv")
            df.to_csv(path, index=False)
            # Derive the answer from the serialized input that the submission sees.
            serialized_df = pd.read_csv(path)
            assert_exact_status(path, expected_status(serialized_df))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
