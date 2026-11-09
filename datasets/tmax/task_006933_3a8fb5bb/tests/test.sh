#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import tokenize

import numpy as np
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

PIPELINE_PATH = "/home/user/pipeline.py"
RESULTS_PATH = "/home/user/results.json"
HDF_PATH = "/home/user/processed_data.h5"
DATA_DIR = "/home/user/data_chunks"
ALPHAS = [0.01, 0.1, 1.0, 10.0, 100.0]


def load_inputs():
    paths = [os.path.join(DATA_DIR, f"chunk_{i}.csv") for i in range(5)]
    frames = [pd.read_csv(path) for path in sorted(paths)]
    return pd.concat(frames, ignore_index=True)


def calculate_expected(df):
    X = df.drop(columns=["target"])
    y = df["target"]
    model = Pipeline([
        ("scaler", StandardScaler()),
        ("ridge", Ridge()),
    ])
    search = GridSearchCV(
        model,
        {"ridge__alpha": ALPHAS},
        cv=5,
    )
    search.fit(X, y)
    return float(search.best_params_["ridge__alpha"]), round(float(search.best_score_), 4)


def run_pipeline():
    assert os.path.isfile(PIPELINE_PATH), f"File {PIPELINE_PATH} is missing."
    with tokenize.open(PIPELINE_PATH) as source_file:
        source = source_file.read()
    compile(source, PIPELINE_PATH, "exec")

    for path in (RESULTS_PATH, HDF_PATH):
        if os.path.lexists(path):
            os.remove(path)

    env = os.environ.copy()
    env.update({
        "OMP_NUM_THREADS": "1",
        "OPENBLAS_NUM_THREADS": "1",
        "MKL_NUM_THREADS": "1",
        "NUMEXPR_NUM_THREADS": "1",
    })
    completed = subprocess.run(
        ["python3", PIPELINE_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"pipeline.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def read_results():
    assert os.path.isfile(RESULTS_PATH), f"File {RESULTS_PATH} is missing."
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_PATH} is not a valid JSON file.")


def validate_artifacts(expected_df, expected_alpha, expected_score):
    results = read_results()

    assert "best_alpha" in results, "Key 'best_alpha' missing from results.json."
    assert "best_score" in results, "Key 'best_score' missing from results.json."
    assert set(results.keys()) == {"best_alpha", "best_score"}, (
        "results.json must have exactly the keys 'best_alpha' and 'best_score'."
    )
    assert isinstance(results["best_alpha"], (int, float)), "'best_alpha' must be a number."
    assert isinstance(results["best_score"], (int, float)), "'best_score' must be a number."
    assert type(results["best_alpha"]) is float, "'best_alpha' must be a float."
    assert type(results["best_score"]) is float, "'best_score' must be a float."
    assert float(results["best_alpha"]) == expected_alpha, (
        f"Expected best_alpha to be {expected_alpha}, got {results['best_alpha']}"
    )
    assert float(results["best_score"]) == expected_score, (
        f"Expected best_score to be {expected_score}, got {results['best_score']}"
    )

    assert os.path.isfile(HDF_PATH), f"File {HDF_PATH} is missing."
    with open(HDF_PATH, "rb") as f:
        magic = f.read(8)
        assert magic == b"\x89HDF\r\n\x1a\n", (
            f"File {HDF_PATH} is not a valid HDF5 file (invalid signature)."
        )
    assert os.path.getsize(HDF_PATH) > 1000, (
        f"File {HDF_PATH} is too small to contain the dataset."
    )

    try:
        stored = pd.read_hdf(HDF_PATH, key="dataset")
    except Exception as exc:
        pytest.fail(f"Could not load key 'dataset' from {HDF_PATH}: {exc}")
    assert_frame_equal(
        stored.reset_index(drop=True),
        expected_df.reset_index(drop=True),
        check_dtype=True,
        check_exact=True,
    )


ORIGINAL_DF = load_inputs()
ORIGINAL_ALPHA, ORIGINAL_SCORE = calculate_expected(ORIGINAL_DF)


@pytest.fixture(scope="session", autouse=True)
def execute_original_pipeline():
    run_pipeline()


def test_results_json_exists_and_valid():
    results = read_results()
    assert "best_alpha" in results, "Key 'best_alpha' missing from results.json."
    assert "best_score" in results, "Key 'best_score' missing from results.json."
    assert isinstance(results["best_alpha"], (int, float)), "'best_alpha' must be a number."
    assert isinstance(results["best_score"], (int, float)), "'best_score' must be a number."
    assert set(results.keys()) == {"best_alpha", "best_score"}


def test_results_json_values():
    results = read_results()

    # Preserve the original checks for the supplied dataset.
    assert float(results["best_alpha"]) == 10.0, (
        f"Expected best_alpha to be 10.0, got {results['best_alpha']}"
    )
    score = float(results["best_score"])
    assert 0.98 < score < 0.99, (
        f"Expected best_score to be around 0.9855, got {score}"
    )

    assert float(results["best_alpha"]) == ORIGINAL_ALPHA
    assert score == ORIGINAL_SCORE


def test_processed_data_h5_exists_and_valid():
    validate_artifacts(ORIGINAL_DF, ORIGINAL_ALPHA, ORIGINAL_SCORE)


def test_pipeline_recomputes_outputs_for_changed_csv_inputs():
    chunk_paths = [os.path.join(DATA_DIR, f"chunk_{i}.csv") for i in range(5)]
    backups = {}
    for path in chunk_paths:
        with open(path, "rb") as f:
            backups[path] = f.read()

    try:
        rng = np.random.RandomState(8675309)
        X = rng.normal(size=(375, 4))
        y = 6.0 * X[:, 0] - 1.75 * X[:, 1] + 0.25 * X[:, 2] + 2.5 * X[:, 3]
        challenge = pd.DataFrame(X, columns=["f1", "f2", "f3", "f4"])
        challenge["target"] = y

        for i, path in enumerate(chunk_paths):
            challenge.iloc[i * 75:(i + 1) * 75].to_csv(path, index=False)

        challenge_df = load_inputs()
        challenge_alpha, challenge_score = calculate_expected(challenge_df)
        assert challenge_alpha != 10.0, "Internal challenge data did not change the optimum."

        run_pipeline()
        validate_artifacts(challenge_df, challenge_alpha, challenge_score)
    finally:
        for path, contents in backups.items():
            with open(path, "wb") as f:
                f.write(contents)
        run_pipeline()
        validate_artifacts(ORIGINAL_DF, ORIGINAL_ALPHA, ORIGINAL_SCORE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
