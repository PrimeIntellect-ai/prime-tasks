#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import numpy as np
import pandas as pd

PROJECT = "/app/linreg_pipeline"
FEATURES = "/app/data/features.csv"
TARGETS = "/app/data/targets.csv"
HIDDEN_TARGETS = "/tests/test_targets_hidden.csv"
PREDICTIONS = f"{PROJECT}/predictions.csv"


def run_pipeline():
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Pipeline failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(PREDICTIONS), (
        f"The predictions file {PREDICTIONS} does not exist. Did you run the pipeline?"
    )


def read_predictions():
    try:
        frame = pd.read_csv(PREDICTIONS)
    except Exception as exc:
        raise AssertionError(f"Failed to read predictions CSV: {exc}")
    assert "id" in frame.columns and "prediction" in frame.columns, (
        "predictions.csv must contain id and prediction columns"
    )
    assert frame["id"].is_unique, "Prediction IDs must be unique"
    assert np.isfinite(frame["prediction"].to_numpy(dtype=float)).all(), (
        "Predictions must be finite numbers"
    )
    return frame


def test_pipeline_behavior_and_original_mse():
    assert os.path.isfile(f"{PROJECT}/Cargo.toml"), "Missing Rust project"
    assert os.path.isfile(f"{PROJECT}/src/main.rs"), "Missing Rust source"
    assert os.path.isfile(HIDDEN_TARGETS), "Missing verifier target oracle"

    feature_backup = "/tmp/features.csv.backup"
    target_backup = "/tmp/targets.csv.backup"
    shutil.copy2(FEATURES, feature_backup)
    shutil.copy2(TARGETS, target_backup)

    custom_predictions = None
    custom_expected = None
    custom_ids = None
    custom_error = None

    try:
        # This fixture includes missing integer values, shuffled target rows, and
        # nonzero residuals. A working pipeline must drop the missing rows, join
        # by ID, and emit the least-squares predictions rather than target copies.
        custom_features = pd.DataFrame({
            "id": [41, 7, 99, 3, 18, 55, 62, 24],
            "f1": [1.0, -2.0, 0.5, 3.0, -1.5, 2.5, 0.25, -0.75],
            "f2": [2, 4, np.nan, 1, 3, np.nan, 5, 2],
        })
        target_by_id = {
            41: 8.4,
            7: 7.1,
            99: 1000.0,
            3: 9.8,
            18: 5.0,
            55: -1000.0,
            62: 15.7,
            24: 4.9,
        }
        custom_targets = pd.DataFrame({
            "id": [24, 55, 3, 99, 7, 62, 41, 18],
            "target": [target_by_id[i] for i in [24, 55, 3, 99, 7, 62, 41, 18]],
        })
        custom_features.to_csv(FEATURES, index=False)
        custom_targets.to_csv(TARGETS, index=False)

        valid = custom_features.dropna(subset=["f2"]).copy()
        custom_ids = valid["id"].astype(int).tolist()
        x = valid[["f1", "f2"]].to_numpy(dtype=float)
        y = np.array([target_by_id[i] for i in custom_ids], dtype=float)
        weights = np.linalg.solve(x.T @ x, x.T @ y)
        custom_expected = dict(zip(custom_ids, x @ weights))

        if os.path.exists(PREDICTIONS):
            os.remove(PREDICTIONS)
        run_pipeline()
        custom_predictions = read_predictions().copy()
    except BaseException as exc:
        custom_error = exc
    finally:
        shutil.copy2(feature_backup, FEATURES)
        shutil.copy2(target_backup, TARGETS)
        if os.path.exists(PREDICTIONS):
            os.remove(PREDICTIONS)
        # Re-run on the task's original inputs so the required final artifact is
        # present and the original MSE assertion evaluates that artifact.
        run_pipeline()

    if custom_error is not None:
        raise custom_error

    assert set(custom_predictions["id"].astype(int)) == set(custom_ids), (
        "The pipeline must emit exactly the rows whose integer feature is present"
    )
    observed = dict(zip(
        custom_predictions["id"].astype(int),
        custom_predictions["prediction"].astype(float),
    ))
    for row_id, expected in custom_expected.items():
        assert np.isclose(observed[row_id], expected, rtol=1e-7, atol=1e-7), (
            f"Incorrect least-squares prediction for custom row {row_id}: "
            f"expected {expected}, got {observed[row_id]}"
        )

    # Preserve the original existence and MSE checks, aligned by ID after
    # applying the instruction's required missing-integer-row filter.
    assert os.path.isfile(PREDICTIONS), f"Missing predictions file: {PREDICTIONS}"
    preds_df = read_predictions()
    try:
        targets_df = pd.read_csv(HIDDEN_TARGETS)
    except Exception as exc:
        raise AssertionError(f"Failed to read hidden targets CSV: {exc}")
    features_df = pd.read_csv(FEATURES)

    expected_ids = set(features_df.loc[features_df["f2"].notna(), "id"].astype(int))
    prediction_ids = set(preds_df["id"].astype(int))
    assert prediction_ids == expected_ids, (
        "Predictions must contain exactly the rows remaining after dropping "
        "missing integer-feature values"
    )

    aligned = preds_df.merge(targets_df[["id", "target"]], on="id", how="inner")
    preds_vals = aligned["prediction"].to_numpy(dtype=float)
    targets_vals = aligned["target"].to_numpy(dtype=float)
    assert len(preds_vals) == len(targets_vals) == len(expected_ids), (
        f"Length mismatch after ID alignment: predictions has {len(preds_vals)} rows, "
        f"targets has {len(targets_vals)} rows, expected {len(expected_ids)} rows."
    )

    mse = float(np.mean((targets_vals - preds_vals) ** 2))
    threshold = 0.5
    assert mse <= threshold, (
        f"Mean Squared Error is too high! Expected MSE <= {threshold}, "
        f"but got {mse:.4f}. The bug in the data pipeline might not be fully fixed."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
