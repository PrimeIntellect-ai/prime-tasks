#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import io
import os
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.datasets import make_regression
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

SCRIPT_PATH = "/home/user/evaluate_model.py"
DATA_PATH = "/home/user/data.csv"
MSE_PATH = "/home/user/fixed_mse.txt"
PRED_PATH = "/home/user/predictions.txt"


def csv_bytes_for(X, y):
    df = pd.DataFrame(X, columns=[f"feat_{i}" for i in range(20)])
    df["target"] = y
    buf = io.StringIO()
    df.to_csv(buf, index=False)
    return buf.getvalue().encode()


def expected_original_data():
    X, y = make_regression(n_samples=1000, n_features=20, noise=0.5, random_state=42)
    return csv_bytes_for(X, y)


def derive_answers(data_path):
    df = pd.read_csv(data_path)
    X = df.drop("target", axis=1)
    y = df["target"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    model = Ridge(alpha=1.0, random_state=42)
    model.fit(X_train_scaled, y_train)
    predictions = model.predict(X_test_scaled)
    return f"{mean_squared_error(y_test, predictions):.4f}", [
        f"{value:.4f}" for value in predictions[:10]
    ]


def read_outputs():
    assert os.path.isfile(MSE_PATH), f"File not found: {MSE_PATH}"
    assert os.path.isfile(PRED_PATH), f"File not found: {PRED_PATH}"
    with open(MSE_PATH) as f:
        mse = f.read().strip()
    with open(PRED_PATH) as f:
        predictions = [line.strip() for line in f if line.strip()]
    return mse, predictions


def execute_submission():
    for path in (MSE_PATH, PRED_PATH):
        if os.path.lexists(path):
            os.remove(path)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"evaluate_model.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def numeric_keyword(call, name):
    for keyword in call.keywords:
        if keyword.arg == name and isinstance(keyword.value, ast.Constant):
            return keyword.value.value
    return None


def call_name(call):
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        return call.func.attr
    return None


def verify_source_structure():
    assert os.path.isfile(SCRIPT_PATH), f"File not found: {SCRIPT_PATH}"
    with open(SCRIPT_PATH) as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]

    split_calls = [call for call in calls if call_name(call) == "train_test_split"]
    assert split_calls, "The script must call train_test_split"
    split_call = min(split_calls, key=lambda call: call.lineno)
    assert numeric_keyword(split_call, "test_size") == 0.2
    assert numeric_keyword(split_call, "random_state") == 42

    ridge_calls = [call for call in calls if call_name(call) == "Ridge"]
    assert ridge_calls, "The script must construct a Ridge model"
    assert any(
        numeric_keyword(call, "alpha") == 1.0
        and numeric_keyword(call, "random_state") == 42
        for call in ridge_calls
    ), "Ridge must use alpha=1.0 and random_state=42"

    assert any(call_name(call) == "StandardScaler" for call in calls), (
        "The corrected evaluation must use StandardScaler"
    )

    preprocessing_fits = [
        call for call in calls
        if isinstance(call.func, ast.Attribute)
        and call.func.attr in ("fit", "fit_transform")
    ]
    assert not any(call.lineno < split_call.lineno for call in preprocessing_fits), (
        "A fit or fit_transform occurs before train_test_split, which leaks test data"
    )

    after_split = [call for call in calls if call.lineno > split_call.lineno]
    has_pipeline = any(call_name(call) in ("Pipeline", "make_pipeline") for call in calls)
    has_fit_after = any(
        isinstance(call.func, ast.Attribute) and call.func.attr == "fit"
        for call in after_split
    )
    has_fit_transform_after = any(
        isinstance(call.func, ast.Attribute) and call.func.attr == "fit_transform"
        for call in after_split
    )
    transform_count_after = sum(
        isinstance(call.func, ast.Attribute) and call.func.attr == "transform"
        for call in after_split
    )
    assert (
        (has_pipeline and has_fit_after)
        or (has_fit_transform_after and transform_count_after >= 1)
        or (has_fit_after and transform_count_after >= 2)
    ), "Scaler must be fit on training data and used to transform test data"


@pytest.fixture(scope="module", autouse=True)
def verify_and_execute_submission():
    expected_data = expected_original_data()
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    assert original_data == expected_data, "The original /home/user/data.csv was altered"

    verify_source_structure()

    # Exercise the submitted script on an unpredictable dataset and derive the
    # expected answers independently. Restore the instructed dataset afterward.
    seed = int.from_bytes(os.urandom(4), "big")
    X, y = make_regression(
        n_samples=137, n_features=20, noise=2.75, random_state=seed
    )
    alternate_data = csv_bytes_for(X, y)
    try:
        with open(DATA_PATH, "wb") as f:
            f.write(alternate_data)
        expected_mse, expected_predictions = derive_answers(DATA_PATH)
        execute_submission()
        actual_mse, actual_predictions = read_outputs()
        assert actual_mse == expected_mse
        assert actual_predictions == expected_predictions
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)

    # Execute again on the original dataset so the required final artifacts are
    # generated by the repaired script itself.
    execute_submission()
    with open(DATA_PATH, "rb") as f:
        assert f.read() == expected_data, "evaluate_model.py altered data.csv"


def test_fixed_mse_file():
    """Check if fixed_mse.txt exists and contains the correct MSE."""
    file_path = "/home/user/fixed_mse.txt"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    # The expected MSE when correctly applying scaling after split
    expected_mse = "0.2476"
    assert content == expected_mse, f"Expected MSE to be {expected_mse}, but got {content}"


def test_predictions_file():
    """Check if predictions.txt exists and contains the correct first 10 predictions."""
    file_path = "/home/user/predictions.txt"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 10, f"Expected exactly 10 predictions, but found {len(lines)}"

    # Expected predictions from the correctly fixed pipeline
    expected_preds = [
        "-18.7302",
        "208.5714",
        "-23.7317",
        "127.6698",
        "272.9348",
        "-22.1805",
        "55.3343",
        "54.8967",
        "-139.7925",
        "-292.0583"
    ]

    for i, (actual, expected) in enumerate(zip(lines, expected_preds)):
        assert actual == expected, f"Prediction at line {i+1} expected to be {expected}, but got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
