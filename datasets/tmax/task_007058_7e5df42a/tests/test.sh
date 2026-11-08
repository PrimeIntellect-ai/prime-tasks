#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import stat
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import BayesianRidge
from sklearn.model_selection import GridSearchCV

SCRIPT_PATH = "/home/user/run_etl.sh"
ORIG_PATH = "/home/user/sensor_data.csv"
IMPUTED_PATH = "/home/user/imputed_sensor_data.csv"
PARAMS_PATH = "/home/user/best_params.json"


def recreate_input():
    # Restore the exact dataset supplied by setup so stale or agent-modified input
    # cannot be used to avoid exercising the requested pipeline.
    np.random.seed(42)
    n = 500
    a = np.random.uniform(0, 10, n)
    b = np.random.uniform(0, 10, n)
    c = 2.5 * a - 1.2 * b + np.random.normal(0, 1.0, n)
    df = pd.DataFrame({"id": range(n), "sensor_A": a, "sensor_B": b, "sensor_C": c})
    drop_idx = np.random.choice(n, int(0.2 * n), replace=False)
    df.loc[drop_idx, "sensor_C"] = np.nan
    df.to_csv(ORIG_PATH, index=False)
    return df


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    expected_input = recreate_input()

    for path in (IMPUTED_PATH, PARAMS_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

    env = os.environ.copy()
    # Conflicting initial values ensure the script must contain effective exports.
    env.update({
        "OMP_NUM_THREADS": "7",
        "OPENBLAS_NUM_THREADS": "7",
        "MKL_NUM_THREADS": "7",
    })
    try:
        result = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=240,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"run_etl.sh timed out: {exc}")
    except OSError as exc:
        pytest.fail(f"Could not execute run_etl.sh: {exc}")

    assert result.returncode == 0, (
        f"run_etl.sh exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(IMPUTED_PATH), "run_etl.sh did not generate imputed_sensor_data.csv"
    assert os.path.exists(PARAMS_PATH), "run_etl.sh did not generate best_params.json"

    # The pipeline must not replace or modify its source data.
    actual_input = pd.read_csv(ORIG_PATH)
    pd.testing.assert_frame_equal(actual_input, expected_input, check_exact=True)


def test_run_etl_sh():
    script_path = SCRIPT_PATH
    assert os.path.exists(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "OMP_NUM_THREADS=1" in content, "OMP_NUM_THREADS=1 not found in run_etl.sh"
    assert "OPENBLAS_NUM_THREADS=1" in content, "OPENBLAS_NUM_THREADS=1 not found in run_etl.sh"
    assert "MKL_NUM_THREADS=1" in content, "MKL_NUM_THREADS=1 not found in run_etl.sh"

    # Require actual, uncommented export commands rather than strings in comments.
    for variable in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
        pattern = rf"(?m)^\s*export\s+{variable}\s*=\s*(['\"]?)1\1\s*(?:#.*)?$"
        assert re.search(pattern, content), f"run_etl.sh must export {variable}=1"


def compute_reference():
    original = pd.read_csv(ORIG_PATH)
    observed = original["sensor_C"].notna()
    x_train = original.loc[observed, ["sensor_A", "sensor_B"]]
    y_train = original.loc[observed, "sensor_C"]

    grid_values = [1e-2, 1e-4, 1e-6]
    param_grid = {
        "alpha_1": grid_values,
        "alpha_2": grid_values,
        "lambda_1": grid_values,
        "lambda_2": grid_values,
    }
    search = GridSearchCV(
        BayesianRidge(),
        param_grid=param_grid,
        scoring="neg_mean_squared_error",
        cv=5,
        refit=True,
    )
    search.fit(x_train, y_train)

    missing = ~observed
    means, stds = search.best_estimator_.predict(
        original.loc[missing, ["sensor_A", "sensor_B"]], return_std=True
    )
    return original, observed, search.best_params_, means, stds


def test_best_params_json():
    json_path = PARAMS_PATH
    assert os.path.exists(json_path), f"File {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            params = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    expected_keys = {"alpha_1", "alpha_2", "lambda_1", "lambda_2"}
    assert set(params.keys()) == expected_keys, (
        f"Expected keys {expected_keys} in best_params.json, found {set(params.keys())}"
    )

    _, _, expected_params, _, _ = compute_reference()
    assert params == expected_params, (
        f"Incorrect best hyperparameters: expected {expected_params}, got {params}"
    )


def test_imputed_sensor_data():
    orig_path = ORIG_PATH
    imputed_path = IMPUTED_PATH

    assert os.path.exists(imputed_path), f"File {imputed_path} does not exist."

    with open(orig_path, "r") as f_orig, open(imputed_path, "r") as f_imp:
        reader_orig = csv.DictReader(f_orig)
        reader_imp = csv.DictReader(f_imp)

        expected_columns = ["id", "sensor_A", "sensor_B", "sensor_C", "sensor_C_std"]
        assert reader_imp.fieldnames == expected_columns, (
            f"Expected columns {expected_columns}, got {reader_imp.fieldnames}"
        )

        orig_rows = list(reader_orig)
        imp_rows = list(reader_imp)
        assert len(orig_rows) == len(imp_rows), (
            "Number of rows in imputed data does not match original data."
        )

        for i, (r_orig, r_imp) in enumerate(zip(orig_rows, imp_rows)):
            assert r_orig["id"] == r_imp["id"], f"Row {i}: ID mismatch"
            assert r_orig["sensor_A"] == r_imp["sensor_A"], f"Row {i}: sensor_A mismatch"
            assert r_orig["sensor_B"] == r_imp["sensor_B"], f"Row {i}: sensor_B mismatch"

            c_std = float(r_imp["sensor_C_std"])
            if r_orig["sensor_C"] == "":
                assert r_imp["sensor_C"] != "", f"Row {i}: sensor_C was not imputed"
                assert c_std > 0.0, (
                    f"Row {i}: sensor_C_std should be > 0.0 for imputed values, got {c_std}"
                )
            else:
                assert abs(float(r_orig["sensor_C"]) - float(r_imp["sensor_C"])) < 1e-6, (
                    f"Row {i}: sensor_C was changed but originally not missing"
                )
                assert c_std == 0.0, (
                    f"Row {i}: sensor_C_std should be 0.0 for existing values, got {c_std}"
                )

    original, observed, _, expected_means, expected_stds = compute_reference()
    result = pd.read_csv(imputed_path)

    assert list(result.columns) == ["id", "sensor_A", "sensor_B", "sensor_C", "sensor_C_std"]
    assert len(result) == len(original)
    assert np.array_equal(result["id"].to_numpy(), original["id"].to_numpy())
    np.testing.assert_allclose(result["sensor_A"], original["sensor_A"], rtol=0, atol=0)
    np.testing.assert_allclose(result["sensor_B"], original["sensor_B"], rtol=0, atol=0)
    np.testing.assert_allclose(
        result.loc[observed, "sensor_C"], original.loc[observed, "sensor_C"], rtol=0, atol=1e-12
    )
    np.testing.assert_allclose(result.loc[observed, "sensor_C_std"], 0.0, rtol=0, atol=0)

    missing = ~observed
    actual_means = result.loc[missing, "sensor_C"].to_numpy()
    actual_stds = result.loc[missing, "sensor_C_std"].to_numpy()
    assert np.all(np.isfinite(actual_means)), "Imputed means must all be finite"
    assert np.all(np.isfinite(actual_stds)), "Predicted standard deviations must all be finite"
    np.testing.assert_allclose(actual_means, expected_means, rtol=1e-6, atol=1e-6)
    np.testing.assert_allclose(actual_stds, expected_stds, rtol=1e-6, atol=1e-6)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
