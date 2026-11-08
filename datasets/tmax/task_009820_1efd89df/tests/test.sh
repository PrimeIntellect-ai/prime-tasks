#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import sys

import pandas as pd
from sklearn.datasets import make_classification
from sklearn.decomposition import PCA
from sklearn.linear_model import RidgeClassifier
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import GridSearchCV
from sklearn.pipeline import Pipeline

HOME = "/home/user"
DATA_PATH = os.path.join(HOME, "data.csv")
SCRIPT_PATH = os.path.join(HOME, "process.py")
BEST_PATH = os.path.join(HOME, "best_n.txt")
MSE_PATH = os.path.join(HOME, "mse.txt")
CANDIDATES = [5, 10, 15, 20]


def reference_results():
    df = pd.read_csv(DATA_PATH)
    X = df.drop(columns=["target"])
    y = df["target"]

    pipeline = Pipeline([
        ("pca", PCA()),
        ("classifier", RidgeClassifier(random_state=42)),
    ])
    search = GridSearchCV(
        pipeline,
        {"pca__n_components": CANDIDATES},
        cv=5,
    )
    search.fit(X, y)
    best_n = int(search.best_params_["pca__n_components"])

    pca = PCA(n_components=best_n)
    reduced = pca.fit_transform(X)
    reconstructed = pca.inverse_transform(reduced)
    mse = mean_squared_error(X, reconstructed)
    return str(best_n), f"{mse:.4f}"


def run_submission(expected_best, expected_mse):
    for path in (BEST_PATH, MSE_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"process.py exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(BEST_PATH), f"File not created by process.py: {BEST_PATH}"
    assert os.path.isfile(MSE_PATH), f"File not created by process.py: {MSE_PATH}"

    with open(BEST_PATH, "r") as f:
        actual_best = f.read().strip()
    with open(MSE_PATH, "r") as f:
        actual_mse = f.read().strip()

    assert actual_best == expected_best, (
        f"Grid-search result is incorrect: expected {expected_best}, got {actual_best!r}"
    )
    assert actual_mse == expected_mse, (
        f"Reconstruction MSE is incorrect: expected {expected_mse}, got {actual_mse!r}"
    )


def test_process_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found: {SCRIPT_PATH}"
    original_data = open(DATA_PATH, "rb").read()

    try:
        # Exercise the submitted script on an unpredictable compatible dataset so
        # prewritten or hard-coded answer files cannot satisfy the verifier.
        seed = secrets.randbelow(2**31 - 1)
        X, y = make_classification(
            n_samples=200,
            n_features=30,
            n_informative=10,
            n_redundant=10,
            random_state=seed,
        )
        alt = pd.DataFrame(X, columns=[f"feat_{i}" for i in range(30)])
        alt["target"] = y
        alt.to_csv(DATA_PATH, index=False)
        expected_best, expected_mse = reference_results()
        run_submission(expected_best, expected_mse)

        # Run again on the provided dataset and leave its required outputs in place.
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        expected_best, expected_mse = reference_results()
        run_submission(expected_best, expected_mse)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)


def test_best_n_file():
    best_n_path = "/home/user/best_n.txt"
    assert os.path.isfile(best_n_path), f"File not found: {best_n_path}"

    with open(best_n_path, "r") as f:
        content = f.read().strip()

    assert content.isdigit(), f"Expected an integer in {best_n_path}, got '{content}'"
    best_n = int(content)
    assert best_n in [5, 10, 15, 20], f"Expected best_n to be one of [5, 10, 15, 20], got {best_n}"


def test_mse_file():
    mse_path = "/home/user/mse.txt"
    assert os.path.isfile(mse_path), f"File not found: {mse_path}"

    with open(mse_path, "r") as f:
        content = f.read().strip()

    # Check if it's a valid float rounded to 4 decimal places
    assert re.match(r"^\d+\.\d{4}$", content), f"Expected MSE to be a float rounded to exactly 4 decimal places, got '{content}'"

    try:
        mse = float(content)
    except ValueError:
        assert False, f"Could not parse '{content}' as a float"

    assert mse >= 0.0, "MSE cannot be negative"


def test_script_exists():
    script_path = "/home/user/process.py"
    assert os.path.isfile(script_path), f"Script not found: {script_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
